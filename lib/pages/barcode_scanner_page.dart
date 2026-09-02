import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pwa/components/app_header.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/theme.dart';
import 'package:pwa/utils/barcode_validator.dart';
import 'package:pwa/utils/camera_focus.dart';
import 'package:pwa/utils/scan_voter.dart';
import 'package:pwa/utils/web_barcode_poller.dart';

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: kIsWeb ? 350 : 250,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128, // GS1-128
    ],
    cameraResolution: kIsWeb ? null : const Size(1920, 1080),
    autoZoom: true,
    returnImage: false,
  );

  /// Serializes camera stop/start across page instances. The web plugin is a
  /// singleton — overlapping stop+start is why the camera only worked once.
  static Future<void> _cameraSession = Future<void>.value();

  final ScanVoter _voter = ScanVoter();
  final WebBarcodePoller _webPoller = WebBarcodePoller();

  bool _didReturn = false;
  Future<void>? _shutdownFuture;
  MobileScannerException? _lastError;
  bool _torchBusy = false;
  bool _webTorchOn = false;
  /// 1.0 or 2.0 — web cannot use [MobileScannerController.setZoomScale].
  double _previewZoom = 1.0;
  bool _webHardwareZoom = false;

  String? _statusValue;
  int _statusHits = 0;
  bool _barcodeFound = false;
  Timer? _statusIdleTimer;
  Size _previewSize = Size.zero;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      MobileScannerPlatform.instance.setWebBarcodeReader(WebBarcodeReader.auto);
    }
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ensureCameraStarted());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_didReturn) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _syncWebPreviewCss();
        unawaited(_ensureCameraStarted());
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

  Future<void> _ensureCameraStarted() async {
    await _cameraSession;
    if (!mounted || _didReturn) return;
    if (_controller.value.isRunning || _controller.value.isStarting) return;

    try {
      await releaseWebCameraTracks();
      if (!mounted || _didReturn) return;
      await _controller.start();
      _syncWebPreviewCss();
      _syncWebPoller();
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
        await _controller.start();
        _syncWebPreviewCss();
        _syncWebPoller();
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
    });
    _statusIdleTimer?.cancel();
    _voter.reset();
    _shutdownFuture = null;
    _cameraSession = _shutdownCamera();
    await _cameraSession;
    _shutdownFuture = null;
    _didReturn = false;
    await _ensureCameraStarted();
  }

  Future<void> _leaveScanner({required VoidCallback afterStop}) async {
    if (_didReturn) return;
    _didReturn = true;
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
    for (final barcode in capture.barcodes) {
      final raw = (barcode.rawValue ?? barcode.displayValue)?.trim();
      if (raw == null || raw.isEmpty) continue;
      if (_considerDecoded(raw)) return;
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

  /// Wide center band used only on web to upscale 1D bars. Not a UI frame.
  Rect _webDecodeRectFor(Size size) {
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: (size.width * 0.92).clamp(1.0, size.width),
      height: (size.height * 0.50).clamp(1.0, size.height),
    );
  }

  void _syncWebPoller([Size? previewSize]) {
    if (!kIsWeb || !mounted || _didReturn) return;
    final size = previewSize ?? _previewSize;
    if (size == Size.zero) return;
    final crop = _webDecodeRectFor(size);
    _webPoller.setScanRegion(previewSize: size, cropInPreview: crop);
    if (_webPoller.isRunning) return;
    _webPoller.start(
      onCode: (value) {
        _considerDecoded(value);
      },
      previewSize: size,
      cropInPreview: crop,
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
                  'Torch is not available in iPhone/iPad browsers. Use Chrome on Android, or the back camera.',
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

  Future<void> _setZoom(double factor) async {
    final next = factor <= 1.0 ? 1.0 : 2.0;
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
      // plugin has settled so 2x is not overwritten.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (mounted) _syncWebPreviewCss();
      return;
    }

    try {
      await _controller.setZoomScale(next <= 1.0 ? 0.0 : 0.5);
    } catch (e) {
      debugPrint('Zoom failed: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusIdleTimer?.cancel();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppImpactHeader(
        title: 'Scan barcode',
        tone: AppHeaderTone.dark,
        actions: [
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
                      _syncWebPoller(areaSize);
                    }
                  });
                }
                return MobileScanner(
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
                zoomed: kIsWeb ? _previewZoom > 1.0 : state.zoomScale >= 0.25,
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

class _ScanStatusBar extends StatelessWidget {
  const _ScanStatusBar({
    required this.status,
    required this.value,
    required this.hits,
    required this.needed,
    required this.zoomed,
    required this.onZoom,
  });

  final _ScanUiStatus status;
  final String? value;
  final int hits;
  final int needed;
  final bool zoomed;
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
        return 'Waiting for barcode';
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
        return 'Point the camera at a product barcode';
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
                      maxLines: 1,
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
              _ZoomToggle(zoomed: zoomed, onZoom: onZoom!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ZoomToggle extends StatelessWidget {
  const _ZoomToggle({
    required this.zoomed,
    required this.onZoom,
  });

  final bool zoomed;
  final Future<void> Function(double factor) onZoom;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ZoomChip(
            label: '1x',
            selected: !zoomed,
            onTap: () => onZoom(1.0),
          ),
          _ZoomChip(
            label: '2x',
            selected: zoomed,
            onTap: () => onZoom(2.0),
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
