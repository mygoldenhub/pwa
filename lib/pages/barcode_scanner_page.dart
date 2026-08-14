import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pwa/components/app_header.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/theme.dart';
import 'package:pwa/utils/camera_focus.dart';
import 'package:pwa/utils/web_barcode_poller.dart';

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  late final MobileScannerController _controller = MobileScannerController(
    autoStart: true,
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.unrestricted,
    // Empty = all formats. Restricting formats can miss EAN-13 on some backends.
    formats: const [],
    cameraResolution: const Size(1920, 1080),
  );

  final WebBarcodePoller _webPoller = WebBarcodePoller();

  bool _didReturn = false;
  MobileScannerException? _lastError;
  bool _webControlsProbed = false;
  WebCameraCapabilities _webCaps = const WebCameraCapabilities.unsupported();

  Size _previewSize = Size.zero;
  Rect? _liveBarcodeRect;
  String? _liveBarcodeValue;
  Timer? _liveClearTimer;
  Timer? _returnTimer;

  /// Normalized zoom 0..1. Used by pinch + slider.
  double _zoom = 0.0;
  double _pinchStartZoom = 0.0;
  bool _torchOn = false;
  bool _torchBusy = false;

  static const double _previewZoomMin = 1.0;
  static const double _previewZoomMax = 3.0;

  double get _previewZoomScale =>
      _previewZoomMin + (_previewZoomMax - _previewZoomMin) * _zoom;

  /// Use Flutter preview zoom when hardware zoom is unavailable (typical on web).
  bool get _usePreviewZoom => kIsWeb ? !_webCaps.supportsZoom : false;

  /// mobile_scanner CSS-mirrors front/desktop cameras. Only undo that mirror.
  /// Rear cameras on phones are already unmirrored — flipping them again
  /// would reverse the live preview and the white-frame crop.
  bool get _unmirrorWebPreview => kIsWeb && webPreviewIsMirrored();

  Rect _guideRectFor(Size size) {
    // EAN-13 is wide and short — keep a wide horizontal capture band.
    final width = (size.width * 0.88).clamp(260.0, 720.0);
    final height = (size.height * 0.32).clamp(140.0, 280.0);
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: width,
      height: height,
    );
  }

  double get _decoderPreviewZoom =>
      _usePreviewZoom ? _previewZoomScale : 1.0;

  /// Guide in camera-widget space. Preview zoom scales the camera under a
  /// fixed on-screen frame, so the live decode region shrinks toward center.
  Rect _decodeGuideRect(Size size) {
    final guide = _guideRectFor(size).inflate(8);
    final zoom = _decoderPreviewZoom;
    if (zoom <= 1.001) return guide;
    return Rect.fromCenter(
      center: guide.center,
      width: guide.width / zoom,
      height: guide.height / zoom,
    );
  }

  void _syncWebScanRegion([Size? previewSize]) {
    final size = previewSize ?? _previewSize;
    if (size == Size.zero) return;
    _webPoller.setScanRegion(
      previewSize: size,
      cropInPreview: _guideRectFor(size).inflate(8),
      previewZoom: _decoderPreviewZoom,
    );
  }

  @override
  void initState() {
    super.initState();
    // Prefer native BarcodeDetector on Chrome; fall back to zxing-wasm.
    // ManyCam / on-screen EAN-13 often works better with the native detector.
    if (kIsWeb) {
      MobileScannerPlatform.instance.setWebBarcodeReader(WebBarcodeReader.auto);
    }
    _controller.addListener(_onControllerUpdate);
  }

  void _onControllerUpdate() {
    final state = _controller.value;
    if (!mounted) return;

    if (state.isRunning && _lastError != null) {
      setState(() => _lastError = null);
    }

    if (!kIsWeb) {
      final on = state.torchState == TorchState.on;
      if (on != _torchOn) setState(() => _torchOn = on);
    }

    if (kIsWeb && state.isRunning && !_webControlsProbed) {
      _webControlsProbed = true;
      unawaited(_probeWebControls());
    }
  }

  Future<void> _probeWebControls() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    var caps = await enableContinuousCameraFocus();
    if (!mounted) return;

    final nativeSupported = await _webPoller.isSupported;

    setState(() {
      _webCaps = caps;
    });

    // Capabilities (especially torch) can appear a moment after the track is live.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    caps = probeWebCameraCapabilities();
    if (caps.supportsTorch != _webCaps.supportsTorch ||
        caps.supportsZoom != _webCaps.supportsZoom) {
      setState(() => _webCaps = caps);
    }

    // Parallel Chrome BarcodeDetector loop, cropped to the white frame only.
    if (nativeSupported && !_webPoller.isRunning) {
      final crop = _previewSize == Size.zero
          ? Rect.zero
          : _guideRectFor(_previewSize).inflate(8);
      _webPoller.start(
        onCode: (value) => _handleDecodedValue(value),
        previewSize: _previewSize,
        cropInPreview: crop,
        previewZoom: _decoderPreviewZoom,
      );
    }
  }

  Future<void> _restartScanner() async {
    if (!mounted) return;
    setState(() {
      _lastError = null;
      _webControlsProbed = false;
      _webCaps = const WebCameraCapabilities.unsupported();
      _torchOn = false;
    });
    try {
      await _controller.stop();
    } catch (e) {
      debugPrint('Failed to stop scanner before retry: $e');
    }
    try {
      await _controller.start();
      if (kIsWeb) {
        await _probeWebControls();
        _webControlsProbed = true;
      }
    } catch (e) {
      debugPrint('Failed to restart scanner: $e');
      if (!mounted) return;
      setState(() {
        _lastError = e is MobileScannerException ? e : null;
      });
    }
  }

  void _goToCart() {
    if (!mounted) return;
    _didReturn = true;
    _returnTimer?.cancel();
    if (kIsWeb && _torchOn) unawaited(setWebTorch(false));
    _webPoller.stop();
    try {
      _controller.stop();
    } catch (e) {
      debugPrint('Failed to stop scanner before leaving: $e');
    }
    if (context.canPop()) {
      context.pop<String?>();
    } else {
      context.go(AppRoutes.cart);
    }
  }

  void _openBarcodeResult(String value) {
    if (_didReturn) return;
    _didReturn = true;
    _returnTimer?.cancel();
    _liveClearTimer?.cancel();
    if (kIsWeb && _torchOn) unawaited(setWebTorch(false));
    _webPoller.stop();
    HapticFeedback.mediumImpact();
    try {
      _controller.stop();
    } catch (e) {
      debugPrint('Failed to stop scanner before result page: $e');
    }
    context.go(AppRoutes.barcodeResult(value));
  }

  Rect? _mapBarcodeToPreview(Barcode barcode, Size captureSize) {
    if (barcode.corners.isEmpty || captureSize.isEmpty || _previewSize.isEmpty) {
      return null;
    }

    final scaleX = _previewSize.width / captureSize.width;
    final scaleY = _previewSize.height / captureSize.height;
    final scale = scaleX > scaleY ? scaleX : scaleY;
    final dx = (_previewSize.width - captureSize.width * scale) / 2;
    final dy = (_previewSize.height - captureSize.height * scale) / 2;

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final p in barcode.corners) {
      final x = p.dx * scale + dx;
      final y = p.dy * scale + dy;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
    if (!minX.isFinite || !maxX.isFinite) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY).inflate(8);
  }

  bool _barcodeIsInGuide(Rect? mapped, Rect guideRect) {
    if (mapped == null) return false;
    // Require the decoded box to sit mostly inside the white frame.
    final overlap = mapped.intersect(guideRect);
    if (overlap.isEmpty) return false;
    final overlapArea = overlap.width * overlap.height;
    final barcodeArea = mapped.width * mapped.height;
    if (barcodeArea <= 0) return false;
    return overlapArea >= barcodeArea * 0.55;
  }

  void _handleDecodedValue(String raw, {Rect? mapped}) {
    if (_didReturn) return;
    final value = raw.trim();
    if (value.isEmpty) return;

    debugPrint('Barcode accepted in frame: $value');

    setState(() {
      _liveBarcodeValue = value;
      _liveBarcodeRect = mapped ??
          (_previewSize == Size.zero ? null : _guideRectFor(_previewSize));
    });

    _returnTimer ??= Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _openBarcodeResult(value);
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (_didReturn) return;
    if (capture.barcodes.isEmpty) return;
    if (_previewSize == Size.zero) return;

    final guideRect = _decodeGuideRect(_previewSize);

    for (final barcode in capture.barcodes) {
      final raw = (barcode.rawValue ?? barcode.displayValue)?.trim();
      if (raw == null || raw.isEmpty) continue;

      final mapped = _mapBarcodeToPreview(barcode, capture.size);
      // No corner data (common on some web backends) — skip this hit so we
      // don't accept barcodes from outside the white frame. The cropped
      // poller still reads codes that sit in the rectangle.
      if (mapped == null) continue;
      if (!_barcodeIsInGuide(mapped, guideRect)) continue;

      setState(() => _liveBarcodeRect = mapped);
      _handleDecodedValue(raw, mapped: mapped);
      return;
    }
  }

  Widget _buildCameraLayer({
    required Widget scanner,
    required Rect? recognitionRect,
  }) {
    final content = Stack(
      fit: StackFit.expand,
      children: [
        scanner,
        if (recognitionRect != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RecognitionRectPainter(rect: recognitionRect),
              ),
            ),
          ),
      ],
    );

    final sx = (_unmirrorWebPreview ? -1.0 : 1.0) * (_usePreviewZoom ? _previewZoomScale : 1.0);
    final sy = _usePreviewZoom ? _previewZoomScale : 1.0;

    if (sx == 1.0 && sy == 1.0) return content;

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..scaleByDouble(sx, sy, 1, 1),
      child: content,
    );
  }

  Future<void> _applyZoom(double normalized) async {
    final next = normalized.clamp(0.0, 1.0);
    setState(() => _zoom = next);
    _syncWebScanRegion();

    if (kIsWeb && _webCaps.supportsZoom) {
      await setWebCameraZoom(next);
      return;
    }
    if (!kIsWeb) {
      try {
        await _controller.setZoomScale(next);
      } catch (e) {
        debugPrint('Zoom not supported: $e');
      }
    }
  }

  Future<void> _toggleTorch() async {
    if (_torchBusy) return;
    _torchBusy = true;
    try {
      if (kIsWeb) {
        // mobile_scanner does not support torch on web. Use MediaTrack
        // constraints. Chrome on Android rear cameras expose `torch`.
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

        final next = !_torchOn;
        final ok = await setWebTorch(next);
        if (!mounted) return;
        if (ok) {
          setState(() {
            _torchOn = next;
            _webCaps = probeWebCameraCapabilities();
          });
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

      final state = _controller.value.torchState;
      if (state == TorchState.unavailable) {
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

  @override
  void dispose() {
    if (kIsWeb && _torchOn) unawaited(setWebTorch(false));
    _liveClearTimer?.cancel();
    _returnTimer?.cancel();
    _webPoller.stop();
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppImpactHeader(
        title: 'Scan barcode',
        tone: AppHeaderTone.dark,
        actions: [
          IconButton(
            tooltip: _torchOn ? 'Torch on' : 'Torch off',
            onPressed: _toggleTorch,
            icon: Icon(
              _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
              color: _torchOn ? Colors.amber : Colors.white,
            ),
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
                      _syncWebScanRegion(areaSize);
                    }
                  });
                }

                final guideRect = _guideRectFor(areaSize);
                final recognitionRect = _liveBarcodeRect;

                final scanner = MobileScanner(
                  controller: _controller,
                  fit: BoxFit.cover,
                  tapToFocus: false,
                  scanWindow: guideRect,
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

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: (details) {
                    _pinchStartZoom = _zoom;
                  },
                  onScaleUpdate: (details) {
                    if (details.pointerCount < 2 && (details.scale - 1).abs() < 0.01) {
                      return;
                    }
                    final startScale = _previewZoomMin +
                        (_previewZoomMax - _previewZoomMin) * _pinchStartZoom;
                    final nextScale =
                        (startScale * details.scale).clamp(_previewZoomMin, _previewZoomMax);
                    final nextZoom =
                        (nextScale - _previewZoomMin) / (_previewZoomMax - _previewZoomMin);
                    unawaited(_applyZoom(nextZoom));
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRect(
                        child: _buildCameraLayer(
                          scanner: scanner,
                          recognitionRect: recognitionRect,
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _GuideFramePainter(cutout: guideRect),
                          ),
                        ),
                      ),
                      if (_liveBarcodeValue != null)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 24,
                          child: IgnorePointer(
                            child: Center(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.72),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white, width: 1.5),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  child: Text(
                                    _liveBarcodeValue!,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.6,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: AppSpacing.paddingLg,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Hold the barcode inside the white frame',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Tip: for on-screen barcodes, zoom so bars are large and sharp',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      const Icon(Icons.zoom_out, color: Colors.white70, size: 18),
                      Expanded(
                        child: Slider(
                          value: _zoom,
                          onChanged: (v) => unawaited(_applyZoom(v)),
                          activeColor: Colors.white,
                          inactiveColor: Colors.white24,
                        ),
                      ),
                      const Icon(Icons.zoom_in, color: Colors.white70, size: 18),
                    ],
                  ),
                  if (_lastError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _restartScanner,
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        label: const Text('Retry camera'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
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
                  kIsWeb
                      ? 'Please allow camera access in your browser.'
                      : 'Please allow camera access and try again.',
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

class _GuideFramePainter extends CustomPainter {
  final Rect cutout;
  _GuideFramePainter({required this.cutout});

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.28);
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final full = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRRect(RRect.fromRectAndRadius(cutout, const Radius.circular(20)));
    canvas.drawPath(Path.combine(PathOperation.difference, full, hole), scrim);
    canvas.drawRRect(RRect.fromRectAndRadius(cutout, const Radius.circular(20)), border);
  }

  @override
  bool shouldRepaint(covariant _GuideFramePainter oldDelegate) => oldDelegate.cutout != cutout;
}

class _RecognitionRectPainter extends CustomPainter {
  final Rect rect;
  _RecognitionRectPainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final fill = Paint()..color = Colors.white.withValues(alpha: 0.08);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.drawRRect(rrect, fill);
    canvas.drawRRect(rrect, border);
  }

  @override
  bool shouldRepaint(covariant _RecognitionRectPainter oldDelegate) => oldDelegate.rect != rect;
}
