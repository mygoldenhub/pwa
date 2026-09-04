import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pwa/components/app_header.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/theme.dart';
import 'package:pwa/utils/barcode_scan_decode.dart';
import 'package:pwa/utils/barcode_validator.dart';
import 'package:pwa/utils/camera_focus.dart';
import 'package:pwa/utils/scan_voter.dart';
import 'package:pwa/utils/web_barcode_poller.dart';

/// Phone-first barcode scanner optimized for difficult product barcodes
/// (glare, distance, tilt, haze, inverted print) on Android, iPhone, and web.
class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage>
    with WidgetsBindingObserver {
  /// Serializes camera stop/start across page instances. The web plugin is a
  /// singleton — overlapping stop+start is why the camera only worked once.
  static Future<void> _cameraSession = Future<void>.value();

  late MobileScannerController _controller;
  final ScanVoter _voter = ScanVoter();
  final WebBarcodePoller _webPoller = WebBarcodePoller();

  bool _didReturn = false;
  Future<void>? _shutdownFuture;
  MobileScannerException? _lastError;
  bool _torchBusy = false;
  bool _webTorchOn = false;
  /// 1.0 / 2.0 / 3.0 — web uses CSS/hardware zoom; native uses setZoomScale.
  double _previewZoom = 1.0;
  bool _webHardwareZoom = false;
  bool _invertImage = false;
  int _controllerGeneration = 0;

  String? _statusValue;
  int _statusHits = 0;
  bool _barcodeFound = false;
  Timer? _statusIdleTimer;
  Timer? _assistTimer;
  DateTime _scanningSince = DateTime.now();
  Size _previewSize = Size.zero;

  /// Last focus target in normalized camera space (0..1). Updated when a
  /// barcode's corners are seen so AF locks onto the code, not the room.
  Offset _focusTarget = const Offset(0.5, 0.45);
  DateTime _lastFocusAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastBarcodeFocusAt = DateTime.fromMillisecondsSinceEpoch(0);
  /// Longer throttle avoids AF hunting (and brief freezes) when the product moves fast.
  static const _focusThrottle = Duration(milliseconds: 700);
  static const _assistInterval = Duration(milliseconds: 2000);
  /// Ignore focus jumps bigger than this — usually means the label is whipping past.
  static const _maxFocusJump = 0.18;

  static const _productFormats = <BarcodeFormat>[
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
    BarcodeFormat.code128, // GS1-128
  ];

  MobileScannerController _buildController({required bool invertImage}) {
    return MobileScannerController(
      autoStart: false,
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.normal,
      // Fast polling: more frames → better chance on tilt / brief blur.
      detectionTimeoutMs: kIsWeb ? 250 : 120,
      formats: _productFormats,
      // High res on Android; web ignores this and uses the browser stream.
      cameraResolution: kIsWeb ? null : const Size(1920, 1080),
      // Zoom is manual only (1x / 2x / 3x). Auto-zoom only zooms in and gets stuck.
      autoZoom: false,
      invertImage: invertImage && !kIsWeb,
      returnImage: false,
    );
  }

  @override
  void initState() {
    super.initState();
    _controller = _buildController(invertImage: false);
    if (kIsWeb) {
      MobileScannerPlatform.instance.setWebBarcodeReader(WebBarcodeReader.auto);
    }
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ensureCameraStarted());
      _armAssist();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_didReturn) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _syncWebPreviewCss();
        unawaited(_ensureCameraStarted());
        _armAssist();
      case AppLifecycleState.inactive:
        // Native: pause the camera when another UI covers the app.
        // Web: permission dialogs and tab focus fire inactive/paused and
        // would kill getUserMedia, causing "Device in use" on the next start.
        if (kIsWeb) return;
        unawaited(_controller.stop());
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _armAssist() {
    _assistTimer?.cancel();
    _scanningSince = DateTime.now();
    // Gentle focus assist only — never stop/restart the camera here.
    // Zoom stays manual (1x / 2x / 3x).
    _assistTimer = Timer.periodic(_assistInterval, (_) {
      unawaited(_runAssistTick());
    });
    unawaited(_runAssistTick());
  }

  Future<void> _requestFocus(
    Offset point, {
    bool force = false,
    bool fromBarcode = false,
  }) async {
    if (!mounted || _didReturn || _barcodeFound) return;
    if (!_controller.value.isRunning) return;

    final now = DateTime.now();
    if (!force && now.difference(_lastFocusAt) < _focusThrottle) return;

    final next = Offset(
      point.dx.clamp(0.05, 0.95),
      point.dy.clamp(0.05, 0.95),
    );

    // Fast product motion makes corner points jump — chasing them freezes AF.
    if (fromBarcode && !force) {
      final dx = (next.dx - _focusTarget.dx).abs();
      final dy = (next.dy - _focusTarget.dy).abs();
      if (dx > _maxFocusJump || dy > _maxFocusJump) {
        return;
      }
    }

    _lastFocusAt = now;
    if (fromBarcode) _lastBarcodeFocusAt = now;
    _focusTarget = next;

    try {
      if (kIsWeb) {
        await requestWebAutoFocus(point: _focusTarget);
      } else {
        await _controller.setFocusPoint(_focusTarget);
      }
    } catch (e) {
      debugPrint('Focus request failed: $e');
    }
  }

  Future<void> _runAssistTick() async {
    if (!mounted || _didReturn || _barcodeFound) return;
    if (!_controller.value.isRunning) return;

    // If we recently locked onto a barcode, don't yank focus back to center.
    final recentlyOnBarcode =
        DateTime.now().difference(_lastBarcodeFocusAt) < const Duration(seconds: 2);
    if (recentlyOnBarcode) return;

    await _requestFocus(_focusTarget, force: true);
    // Intentionally no auto invert / camera rebuild — that suspends the preview.
  }

  /// Normalized focus point from barcode corners in the capture image, or null.
  Offset? _focusPointFromBarcode(Barcode barcode, Size captureSize) {
    if (barcode.corners.length < 2) return null;
    if (captureSize.width <= 0 || captureSize.height <= 0) return null;

    var sumX = 0.0;
    var sumY = 0.0;
    for (final c in barcode.corners) {
      sumX += c.dx;
      sumY += c.dy;
    }
    final cx = sumX / barcode.corners.length;
    final cy = sumY / barcode.corners.length;

    // Corners from ML Kit / Vision are in the camera image coordinate space.
    final nx = cx / captureSize.width;
    final ny = cy / captureSize.height;
    if (nx.isNaN || ny.isNaN) return null;
    if (nx < 0 || nx > 1.2 || ny < 0 || ny > 1.2) return null;
    return Offset(nx.clamp(0.0, 1.0), ny.clamp(0.0, 1.0));
  }

  /// Manual invert for hard glare / reverse-print labels (Android).
  /// Not automatic — rebuilding the camera freezes the preview.
  Future<void> _toggleInvertMode() async {
    if (kIsWeb || _didReturn || _barcodeFound) return;
    final next = !_invertImage;
    await _rebuildController(invertImage: next);
  }

  Future<void> _rebuildController({required bool invertImage}) async {
    await _cameraSession;
    if (!mounted || _didReturn) return;

    _cameraSession = () async {
      _webPoller.stop();
      try {
        await _controller.stop();
      } catch (_) {}
      await releaseWebCameraTracks();
      _controller.dispose();
      _invertImage = invertImage;
      _controllerGeneration++;
      _controller = _buildController(invertImage: invertImage);
      if (mounted) setState(() {});
      // Let MobileScanner attach to the new controller.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted || _didReturn) return;
      await _startCameraInternal();
    }();
    await _cameraSession;
  }

  Future<CameraLensType?> _preferredLens() async {
    if (kIsWeb) return null;
    try {
      return await MobileScannerPlatform.instance
          .getBestCloseRangeScanningLens(facing: CameraFacing.back);
    } catch (e) {
      debugPrint('Close-range lens probe failed: $e');
      return null;
    }
  }

  Future<void> _startCameraInternal() async {
    final lens = await _preferredLens();
    if (!mounted || _didReturn) return;
    await _controller.start(
      cameraDirection: CameraFacing.back,
      cameraLensType: lens,
    );
    _syncWebPreviewCss();
    _syncWebPoller();
    // Re-apply zoom after start (native zoom resets on restart).
    if (!kIsWeb && _previewZoom > 1.0) {
      try {
        await _controller.setZoomScale(_nativeZoomScale(_previewZoom));
      } catch (_) {}
    }
    // Kick continuous / center AF as soon as the stream is live.
    if (kIsWeb) {
      try {
        await enableContinuousCameraFocus();
      } catch (_) {}
    }
    await _requestFocus(_focusTarget, force: true);
  }

  Future<void> _ensureCameraStarted() async {
    await _cameraSession;
    if (!mounted || _didReturn) return;
    if (_controller.value.isRunning || _controller.value.isStarting) return;

    try {
      await releaseWebCameraTracks();
      if (!mounted || _didReturn) return;
      await _startCameraInternal();
      if (mounted && _lastError != null) {
        setState(() => _lastError = null);
      }
    } catch (e) {
      debugPrint('Camera start failed, retrying after release: $e');
      try {
        await _controller.stop();
      } catch (_) {}
      await releaseWebCameraTracks();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted || _didReturn) return;
      try {
        await _startCameraInternal();
        if (mounted && _lastError != null) {
          setState(() => _lastError = null);
        }
      } catch (e2) {
        debugPrint('Camera start retry failed: $e2');
        if (!mounted) return;
        setState(() {
          _lastError = e2 is MobileScannerException ? e2 : null;
        });
      }
    }
  }

  Future<void> _shutdownCamera() {
    return _shutdownFuture ??= () async {
      _assistTimer?.cancel();
      _webPoller.stop();
      if (kIsWeb && _webTorchOn) {
        try {
          await setWebTorch(false);
        } catch (_) {}
      }
      if (kIsWeb) {
        applyWebVideoPreviewStyle(cssZoom: 1.0);
      }
      try {
        await _controller.stop();
      } catch (e) {
        debugPrint('Failed to stop scanner: $e');
      }
      await releaseWebCameraTracks();
    }();
  }

  Future<void> _restartScanner() async {
    if (!mounted) return;
    setState(() {
      _lastError = null;
      _webTorchOn = false;
      _previewZoom = 1.0;
      _webHardwareZoom = false;
      _statusValue = null;
      _statusHits = 0;
      _barcodeFound = false;
      _invertImage = false;
      _focusTarget = const Offset(0.5, 0.45);
    });
    _statusIdleTimer?.cancel();
    _voter.reset();
    _shutdownFuture = null;
    _cameraSession = _shutdownCamera();
    await _cameraSession;
    _controller.dispose();
    _controllerGeneration++;
    _controller = _buildController(invertImage: false);
    _shutdownFuture = null;
    _didReturn = false;
    if (mounted) setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _ensureCameraStarted();
    _armAssist();
  }

  Future<void> _leaveScanner({required VoidCallback afterStop}) async {
    if (_didReturn) return;
    _didReturn = true;
    _assistTimer?.cancel();
    _cameraSession = _shutdownCamera();
    await _cameraSession;
    if (!mounted) return;
    afterStop();
  }

  void _goToCart() {
    unawaited(_leaveScanner(afterStop: () {
      if (!mounted) return;
      if (context.canPop()) {
        context.pop<String?>();
      } else {
        context.go(AppRoutes.cart);
      }
    }));
  }

  void _acceptBarcode(String value) {
    HapticFeedback.mediumImpact();
    unawaited(_leaveScanner(afterStop: () {
      if (!mounted) return;
      context.go(AppRoutes.barcodeResult(value));
    }));
  }

  void _onDetect(BarcodeCapture capture) {
    if (_didReturn) return;

    // Lock AF onto a steady barcode. Skip huge jumps (fast-moving product).
    for (final barcode in capture.barcodes) {
      final point = _focusPointFromBarcode(barcode, capture.size);
      if (point != null) {
        unawaited(_requestFocus(point, fromBarcode: true));
        break;
      }
    }

    for (final barcode in capture.barcodes) {
      for (final raw in BarcodeScanDecode.candidates(barcode)) {
        if (_considerDecoded(raw)) return;
      }
    }
  }

  /// Returns true when the value was accepted and navigation started.
  bool _considerDecoded(String raw) {
    if (_didReturn) return false;
    final value = BarcodeValidator.normalize(raw);
    if (value == null) return false;

    final accepted = _voter.vote(value);
    _statusIdleTimer?.cancel();

    if (accepted != null) {
      setState(() {
        _statusValue = accepted;
        _statusHits = _voter.voteCount;
        _barcodeFound = true;
      });
      _assistTimer?.cancel();
      _acceptBarcode(accepted);
      return true;
    }

    if (!mounted) return false;
    setState(() {
      _statusValue = value;
      _statusHits = _voter.voteCount;
      _barcodeFound = false;
    });
    _statusIdleTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted || _didReturn || _barcodeFound) return;
      setState(() {
        _statusValue = null;
        _statusHits = 0;
      });
    });
    return false;
  }

  /// Decode band for the web poller.
  ///
  /// When CSS zoom is active (no hardware zoom), the live <video> buffer is
  /// still full-frame — so we crop the same center region the user sees and
  /// upscale it for decode. Hardware zoom already crops in-camera.
  Rect _webDecodeRectFor(Size size) {
    final cssZoom = (!_webHardwareZoom && _previewZoom > 1.0) ? _previewZoom : 1.0;
    final widthFrac = (0.96 / cssZoom).clamp(0.30, 0.96);
    final heightFrac = (0.52 / cssZoom).clamp(0.20, 0.55);
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.45),
      width: (size.width * widthFrac).clamp(1.0, size.width),
      height: (size.height * heightFrac).clamp(1.0, size.height),
    );
  }

  double get _webDecodeMagnify {
    // CSS zoom does not change the camera buffer — boost decode upscale instead.
    if (_webHardwareZoom) return 1.0;
    if (_previewZoom >= 2.5) return 3.0;
    if (_previewZoom >= 1.5) return 2.0;
    return 1.0;
  }

  void _syncWebPoller({Size? previewSize, bool forceRestart = false}) {
    if (!kIsWeb || !mounted || _didReturn) return;
    final size = previewSize ?? _previewSize;
    if (size == Size.zero) return;
    final crop = _webDecodeRectFor(size);
    final magnify = _webDecodeMagnify;
    if (_webPoller.isRunning && !forceRestart) {
      _webPoller.updateRegion(
        previewSize: size,
        cropInPreview: crop,
        decodeMagnify: magnify,
      );
      return;
    }
    _webPoller.start(
      onCode: (value) {
        _considerDecoded(value);
      },
      previewSize: size,
      cropInPreview: crop,
      decodeMagnify: magnify,
      interval: const Duration(milliseconds: 80),
    );
  }

  void _syncWebPreviewCss() {
    if (!kIsWeb) return;
    applyWebVideoPreviewStyle(
      cssZoom: _webHardwareZoom ? 1.0 : _previewZoom,
    );
    ensureWebVideoPlaysInline();
  }

  bool get _torchOn {
    if (kIsWeb && _controller.value.torchState == TorchState.unavailable) {
      return _webTorchOn;
    }
    return _controller.value.torchState == TorchState.on;
  }

  Future<void> _toggleTorch() async {
    if (_torchBusy) return;
    _torchBusy = true;
    try {
      if (kIsWeb && _controller.value.torchState == TorchState.unavailable) {
        if (webIsAppleMobile()) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text(
                  'Torch is not available in iPhone/iPad browsers. Use Chrome on Android, or the iOS/Android app.',
                ),
              ),
            );
          return;
        }

        final next = !_webTorchOn;
        final ok = await setWebTorch(next);
        if (!mounted) return;
        if (ok) {
          setState(() => _webTorchOn = next);
        } else {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text(
                  'Torch needs the back camera in Chrome or a supported Android browser.',
                ),
              ),
            );
        }
        return;
      }

      if (_controller.value.torchState == TorchState.unavailable) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('Torch is not available on this device'),
            ),
          );
        return;
      }
      await _controller.toggleTorch();
    } catch (e) {
      debugPrint('Torch toggle failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Torch failed: $e'),
          ),
        );
    } finally {
      _torchBusy = false;
    }
  }

  double _nativeZoomScale(double factor) {
    // Keep zoom inside a quality-friendly band of the camera zoom curve.
    // Aggressive linearZoom (near 1.0) is often pure digital and softens bars.
    if (factor <= 1.0) return 0.0;
    if (factor <= 2.0) return 0.32;
    return 0.55;
  }

  /// After zoom changes: reset votes, retarget AF, and retune web decode crop.
  Future<void> _afterZoomChanged() async {
    if (!mounted || _didReturn || _barcodeFound) return;

    _voter.reset();
    _statusIdleTimer?.cancel();
    _focusTarget = const Offset(0.5, 0.45);
    if (mounted) {
      setState(() {
        _statusValue = null;
        _statusHits = 0;
      });
    }

    _syncWebPoller(forceRestart: false);
    // Zoom changes focus distance — force AF onto the scan guide center.
    await _requestFocus(_focusTarget, force: true);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted || _didReturn || _barcodeFound) return;
    await _requestFocus(_focusTarget, force: true);
  }

  Future<void> _setZoom(double factor) async {
    final next = factor <= 1.0 ? 1.0 : (factor <= 2.0 ? 2.0 : 3.0);
    if (next == _previewZoom && !kIsWeb) {
      // Still re-settle focus if user taps the same level again.
      await _afterZoomChanged();
      return;
    }

    if (kIsWeb) {
      var hardware = false;
      try {
        hardware = await setWebZoomMultiplier(next);
      } catch (e) {
        debugPrint('Web camera zoom skipped: $e');
      }
      if (!mounted) return;
      setState(() {
        _previewZoom = next;
        _webHardwareZoom = hardware;
      });
      _syncWebPreviewCss();
      // mobile_scanner rewrites <video> CSS after start; re-apply once the
      // plugin has settled so zoom is not overwritten.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (mounted) _syncWebPreviewCss();
      await _afterZoomChanged();
      return;
    }

    try {
      await _controller.setZoomScale(_nativeZoomScale(next));
      if (mounted) setState(() => _previewZoom = next);
      await _afterZoomChanged();
    } catch (e) {
      debugPrint('Zoom failed: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusIdleTimer?.cancel();
    _assistTimer?.cancel();
    _cameraSession = _shutdownCamera().whenComplete(() {
      _controller.dispose();
    });
    super.dispose();
  }

  _ScanUiStatus _uiStatus({required bool cameraRunning}) {
    if (_lastError != null) return _ScanUiStatus.error;
    if (_barcodeFound) return _ScanUiStatus.found;
    if (!cameraRunning) return _ScanUiStatus.starting;
    if (_statusHits > 0 && _statusValue != null) return _ScanUiStatus.reading;
    return _ScanUiStatus.waiting;
  }

  String? get _assistHint {
    if (_barcodeFound || _lastError != null) return null;
    final elapsed = DateTime.now().difference(_scanningSince);
    if (elapsed.inSeconds < 3) return null;
    if (_invertImage) return 'Inverted mode on · tap again to turn off';
    if (_previewZoom >= 2.0) {
      return 'Zoom settled · hold steady, or tap 1x if soft / too close';
    }
    if (_statusHits > 0) {
      return 'Almost there · hold steady while focus locks';
    }
    if (!kIsWeb && elapsed.inSeconds >= 8) {
      return 'Tip: try Invert for glare / reverse-print labels';
    }
    if (elapsed.inSeconds >= 5) {
      return 'Tip: hold parallel to the label · avoid extreme side angles';
    }
    return 'Tip: fill the guide with the barcode, tap to focus, or try 2x if far';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppImpactHeader(
        title: 'Scan barcode',
        tone: AppHeaderTone.dark,
        actions: [
          if (!kIsWeb)
            IconButton(
              tooltip: _invertImage ? 'Invert on' : 'Invert (hard labels)',
              onPressed: _toggleInvertMode,
              icon: Icon(
                Icons.invert_colors,
                color: _invertImage ? Colors.amber : Colors.white,
              ),
            ),
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              final on = _torchOn;
              return IconButton(
                tooltip: on ? 'Torch on' : 'Torch off',
                onPressed: _toggleTorch,
                icon: Icon(
                  on ? Icons.flashlight_on : Icons.flashlight_off,
                  color: on ? Colors.amber : Colors.white,
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Back to cart',
            onPressed: _goToCart,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final areaSize = constraints.biggest;
                if (_previewSize != areaSize) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    if (_previewSize != areaSize) {
                      setState(() => _previewSize = areaSize);
                      _syncWebPoller(previewSize: areaSize);
                    }
                  });
                }
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      key: ValueKey('scanner-$_controllerGeneration'),
                      controller: _controller,
                      fit: BoxFit.cover,
                      tapToFocus: !kIsWeb,
                      useAppLifecycleState: false,
                      onDetect: _onDetect,
                      errorBuilder: (context, error) {
                        debugPrint('MobileScanner error: $error');
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          if (_lastError != error) {
                            setState(() => _lastError = error);
                          }
                        });
                        return _ScannerErrorState(
                          error: error,
                          onRetry: _restartScanner,
                          onClose: _goToCart,
                        );
                      },
                    ),
                    // Soft guide — does not crop the decoder, only helps aim.
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _ScanGuidePainter(
                          accent: _barcodeFound
                              ? const Color(0xFF7CFFB1)
                              : Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              return _ScanStatusBar(
                status: _uiStatus(cameraRunning: state.isRunning),
                value: _statusValue,
                hits: _statusHits,
                needed: _voter.requiredHits,
                hint: _assistHint,
                inverted: _invertImage,
                zoomFactor: _previewZoom,
                onZoom: state.isRunning ? _setZoom : null,
              );
            },
          ),
          if (_lastError != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: AppSpacing.paddingLg,
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: _restartScanner,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text('Retry camera'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _ScanUiStatus { starting, waiting, reading, found, error }

class _ScanGuidePainter extends CustomPainter {
  _ScanGuidePainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final band = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.45),
      width: size.width * 0.78,
      height: size.height * 0.18,
    );
    final paint = Paint()
      ..color = accent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const corner = 22.0;
    // Top-left
    canvas.drawLine(band.topLeft, band.topLeft + const Offset(corner, 0), paint);
    canvas.drawLine(band.topLeft, band.topLeft + const Offset(0, corner), paint);
    // Top-right
    canvas.drawLine(band.topRight, band.topRight + const Offset(-corner, 0), paint);
    canvas.drawLine(band.topRight, band.topRight + const Offset(0, corner), paint);
    // Bottom-left
    canvas.drawLine(band.bottomLeft, band.bottomLeft + const Offset(corner, 0), paint);
    canvas.drawLine(band.bottomLeft, band.bottomLeft + const Offset(0, -corner), paint);
    // Bottom-right
    canvas.drawLine(band.bottomRight, band.bottomRight + const Offset(-corner, 0), paint);
    canvas.drawLine(band.bottomRight, band.bottomRight + const Offset(0, -corner), paint);
  }

  @override
  bool shouldRepaint(covariant _ScanGuidePainter oldDelegate) =>
      oldDelegate.accent != accent;
}

class _ScanStatusBar extends StatelessWidget {
  const _ScanStatusBar({
    required this.status,
    required this.value,
    required this.hits,
    required this.needed,
    required this.hint,
    required this.inverted,
    required this.zoomFactor,
    required this.onZoom,
  });

  final _ScanUiStatus status;
  final String? value;
  final int hits;
  final int needed;
  final String? hint;
  final bool inverted;
  final double zoomFactor;
  final Future<void> Function(double factor)? onZoom;

  String get _title {
    switch (status) {
      case _ScanUiStatus.starting:
        return 'Starting camera…';
      case _ScanUiStatus.reading:
        return 'Reading barcode…';
      case _ScanUiStatus.found:
        return 'Barcode found';
      case _ScanUiStatus.error:
        return 'Camera unavailable';
      case _ScanUiStatus.waiting:
        return inverted ? 'Scanning (inverted)' : 'Waiting for barcode';
    }
  }

  String? get _subtitle {
    switch (status) {
      case _ScanUiStatus.reading:
        if (value == null) return 'Hold steady';
        return '$value  ·  $hits/$needed';
      case _ScanUiStatus.found:
        return value;
      case _ScanUiStatus.waiting:
        return hint ?? 'Point the camera at a product barcode';
      case _ScanUiStatus.starting:
      case _ScanUiStatus.error:
        return null;
    }
  }

  IconData get _icon {
    switch (status) {
      case _ScanUiStatus.starting:
        return Icons.camera_alt_outlined;
      case _ScanUiStatus.reading:
        return Icons.qr_code_scanner;
      case _ScanUiStatus.found:
        return Icons.check_circle_outline;
      case _ScanUiStatus.error:
        return Icons.error_outline;
      case _ScanUiStatus.waiting:
        return Icons.document_scanner_outlined;
    }
  }

  Color get _accent {
    switch (status) {
      case _ScanUiStatus.reading:
        return Colors.amber;
      case _ScanUiStatus.found:
        return const Color(0xFF7CFFB1);
      case _ScanUiStatus.error:
        return const Color(0xFFFF8A80);
      case _ScanUiStatus.starting:
      case _ScanUiStatus.waiting:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _subtitle;
    final showMono = status == _ScanUiStatus.reading || status == _ScanUiStatus.found;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          children: [
            Icon(_icon, color: _accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: _accent,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.75),
                            letterSpacing: showMono ? 0.4 : 0,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            if (onZoom != null) ...[
              const SizedBox(width: 8),
              _ZoomToggle(zoomFactor: zoomFactor, onZoom: onZoom!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ZoomToggle extends StatelessWidget {
  const _ZoomToggle({
    required this.zoomFactor,
    required this.onZoom,
  });

  final double zoomFactor;
  final Future<void> Function(double factor) onZoom;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomChip(label: '1x', selected: zoomFactor <= 1.0, onTap: () => onZoom(1.0)),
          _ZoomChip(label: '2x', selected: zoomFactor > 1.0 && zoomFactor < 2.5, onTap: () => onZoom(2.0)),
          _ZoomChip(label: '3x', selected: zoomFactor >= 2.5, onTap: () => onZoom(3.0)),
        ],
      ),
    );
  }
}

class _ZoomChip extends StatelessWidget {
  const _ZoomChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.amber : Colors.white,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _ScannerErrorState extends StatelessWidget {
  final MobileScannerException error;
  final VoidCallback onRetry;
  final VoidCallback onClose;
  const _ScannerErrorState({
    required this.error,
    required this.onRetry,
    required this.onClose,
  });

  String get _message {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return kIsWeb
            ? 'Please allow camera access in your browser.'
            : 'Camera permission was denied. Enable it in settings and try again.';
      default:
        return kIsWeb
            ? 'Please allow camera access in your browser.'
            : 'Please allow camera access and try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: AppSpacing.paddingXl,
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: AppSpacing.paddingXl,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.camera_alt_outlined, color: cs.primary, size: 34),
                const SizedBox(height: AppSpacing.sm),
                Text('Camera unavailable', style: Theme.of(context).textTheme.titleLarge?.semiBold),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _message,
                  style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: Icon(Icons.refresh, color: cs.primary),
                    label: const Text('Retry camera'),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onClose,
                    icon: Icon(Icons.close, color: cs.onPrimary),
                    label: Text('Back to cart', style: TextStyle(color: cs.onPrimary)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
