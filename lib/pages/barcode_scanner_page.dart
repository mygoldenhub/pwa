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

/// Product barcode scanner using stock [mobile_scanner] (ML Kit / Vision / web).
///
/// Lifecycle follows the package README: manual start, barcode stream
/// subscription, and pause/resume via [WidgetsBindingObserver].
class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage>
    with WidgetsBindingObserver {
  static const _productFormats = <BarcodeFormat>[
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
    BarcodeFormat.code128, // GS1-128
  ];

  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.normal,
    formats: _productFormats,
    autoZoom: false,
    returnImage: false,
  );

  StreamSubscription<BarcodeCapture>? _subscription;
  bool _handled = false;
  bool _torchBusy = false;
  MobileScannerException? _lastError;
  String? _statusValue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (kIsWeb) {
      MobileScannerPlatform.instance.setWebBarcodeReader(WebBarcodeReader.auto);
    }

    _subscription = _controller.barcodes.listen(_handleBarcode);
    unawaited(_startScanner());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission dialogs can fire lifecycle events before the controller is ready.
    if (!_controller.value.hasCameraPermission) return;

    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        return;
      case AppLifecycleState.resumed:
        _subscription ??= _controller.barcodes.listen(_handleBarcode);
        unawaited(_startScanner());
      case AppLifecycleState.inactive:
        // Web: tab focus / permission UI fires inactive and would drop getUserMedia.
        if (kIsWeb) return;
        unawaited(_subscription?.cancel());
        _subscription = null;
        unawaited(_controller.stop());
    }
  }

  Future<void> _startScanner() async {
    if (_handled) return;
    try {
      CameraLensType? lens;
      if (!kIsWeb) {
        try {
          lens = await MobileScannerPlatform.instance
              .getBestCloseRangeScanningLens(facing: CameraFacing.back);
        } catch (e) {
          debugPrint('Close-range lens probe failed: $e');
        }
      }
      if (!mounted || _handled) return;
      await _controller.start(
        cameraDirection: CameraFacing.back,
        cameraLensType: lens,
      );
      if (mounted && _lastError != null) {
        setState(() => _lastError = null);
      }
    } catch (e) {
      debugPrint('Camera start failed: $e');
      if (!mounted) return;
      setState(() {
        _lastError = e is MobileScannerException ? e : null;
      });
    }
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_handled || !mounted) return;

    for (final barcode in capture.barcodes) {
      for (final raw in BarcodeScanDecode.candidates(barcode)) {
        final value = BarcodeValidator.normalize(raw);
        if (value == null) continue;

        _handled = true;
        setState(() => _statusValue = value);
        unawaited(_acceptBarcode(value));
        return;
      }
    }
  }

  Future<void> _acceptBarcode(String value) async {
    HapticFeedback.mediumImpact();
    await _shutdown();
    if (!mounted) return;
    context.go(AppRoutes.barcodeResult(value));
  }

  Future<void> _leaveToCart() async {
    if (_handled) return;
    _handled = true;
    await _shutdown();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop<String?>();
    } else {
      context.go(AppRoutes.cart);
    }
  }

  Future<void> _shutdown() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _controller.stop();
    } catch (e) {
      debugPrint('Failed to stop scanner: $e');
    }
  }

  Future<void> _restartScanner() async {
    _handled = false;
    setState(() {
      _lastError = null;
      _statusValue = null;
    });
    try {
      await _controller.stop();
    } catch (_) {}
    await _subscription?.cancel();
    _subscription = _controller.barcodes.listen(_handleBarcode);
    await _startScanner();
  }

  Future<void> _toggleTorch() async {
    if (_torchBusy) return;
    _torchBusy = true;
    try {
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    _subscription = null;
    super.dispose();
    unawaited(_controller.dispose());
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
              final on = state.torchState == TorchState.on;
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
            onPressed: _leaveToCart,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  fit: BoxFit.cover,
                  tapToFocus: !kIsWeb,
                  useAppLifecycleState: false,
                  onDetectError: (error, _) {
                    debugPrint('MobileScanner detect error: $error');
                  },
                  errorBuilder: (context, error) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      if (_lastError != error) {
                        setState(() => _lastError = error);
                      }
                    });
                    return _ScannerErrorState(
                      error: error,
                      onRetry: _restartScanner,
                      onClose: _leaveToCart,
                    );
                  },
                ),
                IgnorePointer(
                  child: CustomPaint(
                    painter: _ScanGuidePainter(
                      accent: _statusValue != null
                          ? const Color(0xFF7CFFB1)
                          : Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              return _ScanStatusBar(
                cameraRunning: state.isRunning,
                error: _lastError != null,
                value: _statusValue,
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
    canvas.drawLine(band.topLeft, band.topLeft + const Offset(corner, 0), paint);
    canvas.drawLine(band.topLeft, band.topLeft + const Offset(0, corner), paint);
    canvas.drawLine(band.topRight, band.topRight + const Offset(-corner, 0), paint);
    canvas.drawLine(band.topRight, band.topRight + const Offset(0, corner), paint);
    canvas.drawLine(band.bottomLeft, band.bottomLeft + const Offset(corner, 0), paint);
    canvas.drawLine(band.bottomLeft, band.bottomLeft + const Offset(0, -corner), paint);
    canvas.drawLine(band.bottomRight, band.bottomRight + const Offset(-corner, 0), paint);
    canvas.drawLine(band.bottomRight, band.bottomRight + const Offset(0, -corner), paint);
  }

  @override
  bool shouldRepaint(covariant _ScanGuidePainter oldDelegate) =>
      oldDelegate.accent != accent;
}

class _ScanStatusBar extends StatelessWidget {
  const _ScanStatusBar({
    required this.cameraRunning,
    required this.error,
    required this.value,
  });

  final bool cameraRunning;
  final bool error;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final String title;
    final String? subtitle;
    final IconData icon;
    final Color accent;

    if (error) {
      title = 'Camera unavailable';
      subtitle = null;
      icon = Icons.error_outline;
      accent = const Color(0xFFFF8A80);
    } else if (value != null) {
      title = 'Barcode found';
      subtitle = value;
      icon = Icons.check_circle_outline;
      accent = const Color(0xFF7CFFB1);
    } else if (!cameraRunning) {
      title = 'Starting camera…';
      subtitle = null;
      icon = Icons.camera_alt_outlined;
      accent = Colors.white;
    } else {
      title = 'Waiting for barcode';
      subtitle = 'Point the camera at a product barcode';
      icon = Icons.document_scanner_outlined;
      accent = Colors.white;
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          children: [
            Icon(icon, color: accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: accent,
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
                            letterSpacing: value != null ? 0.4 : 0,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerErrorState extends StatelessWidget {
  const _ScannerErrorState({
    required this.error,
    required this.onRetry,
    required this.onClose,
  });

  final MobileScannerException error;
  final VoidCallback onRetry;
  final VoidCallback onClose;

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
                Text(
                  'Camera unavailable',
                  style: Theme.of(context).textTheme.titleLarge?.semiBold,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _message,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.withColor(cs.onSurfaceVariant),
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
                    label: Text(
                      'Back to cart',
                      style: TextStyle(color: cs.onPrimary),
                    ),
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
