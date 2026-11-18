import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scankit/flutter_scankit.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/components/app_header.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/services/web_barcode_engine.dart';
import 'package:pwa/theme.dart';
import 'package:pwa/utils/barcode_validator.dart';

/// Product barcode scanner powered by Huawei Scan Kit ([flutter_scankit]).
///
/// Optimized for difficult mobile labels (reflective, dim, blurry, curved).
/// Android and iOS only — web shows an unsupported state.
class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  /// Retail + GS1-128 (Code 128). ITF-14 included for GTIN cartons.
  /// Code 128 must stay enabled — GS1-128 is Code 128 with FNC1.
  static final int _productFormats = ScanTypes.ean8.bit |
      ScanTypes.ean13.bit |
      ScanTypes.upcCodeA.bit |
      ScanTypes.upcCodeE.bit |
      ScanTypes.code128.bit |
      ScanTypes.itf14.bit;

  ScanKitController? _controller;
  StreamSubscription<ScanResult>? _resultSub;
  StreamSubscription<bool>? _lightSub;

  bool _handled = false;
  bool _torchOn = false;
  bool _autoTorchArmed = false;
  String? _statusValue;

  bool get _isMobileNative =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (!_isMobileNative) return;

    final controller = ScanKitController();
    _controller = controller;
    _resultSub = controller.onResult.listen(_onScanResult);

    // Android: Scan Kit reports when the scene is too dark for a reliable read.
    if (defaultTargetPlatform == TargetPlatform.android) {
      _lightSub = controller.onLightVisible.listen((needLight) {
        if (!mounted || _handled || _autoTorchArmed || !needLight) return;
        _autoTorchArmed = true;
        unawaited(_ensureTorchOn());
      });
    }
  }

  Future<void> _ensureTorchOn() async {
    final controller = _controller;
    if (controller == null || _torchOn) return;
    try {
      await controller.switchLight();
      if (!mounted) return;
      setState(() => _torchOn = true);
    } catch (e) {
      debugPrint('Auto torch failed: $e');
    }
  }

  void _onScanResult(ScanResult result) {
    if (_handled || !mounted) return;
    if (result.isEmpty) return;

    final raw = result.originalValue;
    // GS1-128 (AI 01 + optional AI 30, etc.) — try every Scan Kit string form.
    final value = BarcodeValidator.normalize(raw);
    if (value == null) {
      debugPrint(
        'ScanKit ignored raw="${raw.replaceAll('\u001D', '{GS}')}" '
        'type=${result.scanType}',
      );
      // Keep continuous scan running; ignore non-product / bad check-digit reads.
      return;
    }

    debugPrint('ScanKit accepted $value from raw="$raw" type=${result.scanType}');
    _handled = true;
    setState(() => _statusValue = value);
    unawaited(_acceptBarcode(value));
  }

  /// PWA path: [value] is already normalized by [BarcodeValidator].
  void _onWebBarcode(String value) {
    if (_handled || !mounted) return;
    debugPrint('Web scanner accepted $value');
    _handled = true;
    setState(() => _statusValue = value);
    unawaited(_acceptBarcode(value));
  }

  Future<void> _acceptBarcode(String value) async {
    HapticFeedback.mediumImpact();
    // Pause continuous decode before leaving (Android).
    try {
      await _controller?.pauseContinuouslyScan();
    } catch (_) {}
    if (!mounted) return;
    context.go(AppRoutes.barcodeResult(value));
  }

  Future<void> _leaveToCart() async {
    if (_handled) return;
    _handled = true;
    try {
      await _controller?.pauseContinuouslyScan();
    } catch (_) {}
    if (!mounted) return;
    if (context.canPop()) {
      context.pop<String?>();
    } else {
      context.go(AppRoutes.cart);
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.switchLight();
      if (!mounted) return;
      setState(() => _torchOn = !_torchOn);
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
    }
  }

  @override
  void dispose() {
    unawaited(_resultSub?.cancel());
    unawaited(_lightSub?.cancel());
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(controller.dispose());
    }
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
          if (_isMobileNative)
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
            onPressed: _leaveToCart,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
      body: !_isMobileNative
          ? (kIsWeb
              // PWA / phone browser: Scan Kit can't run here, so use the web engine.
              ? _WebScanner(
                  statusValue: _statusValue,
                  onBarcode: _onWebBarcode,
                )
              : _UnsupportedPlatform(
                  onClose: _leaveToCart,
                ))
          : Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.biggest;
                      // Guide only — do NOT pass boundingBox to ScanKit.
                      // The plugin multiplies Flutter logical px by density again,
                      // which shrinks/offsets the native window and breaks wide
                      // GS1-128 labels. Full-frame decode is more reliable.
                      final guide = Rect.fromCenter(
                        center: Offset(size.width / 2, size.height * 0.45),
                        width: size.width * 0.92,
                        height: size.height * 0.22,
                      );
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ScanKitWidget(
                            controller: _controller!,
                            continuouslyScan: true,
                            format: _productFormats,
                          ),
                          IgnorePointer(
                            child: CustomPaint(
                              painter: _ScanGuidePainter(
                                accent: _statusValue != null
                                    ? const Color(0xFF7CFFB1)
                                    : Colors.white.withValues(alpha: 0.85),
                                box: guide,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                _ScanStatusBar(value: _statusValue),
              ],
            ),
    );
  }
}

class _ScanGuidePainter extends CustomPainter {
  _ScanGuidePainter({required this.accent, required this.box});

  final Color accent;
  final Rect box;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const corner = 22.0;
    canvas.drawLine(box.topLeft, box.topLeft + const Offset(corner, 0), paint);
    canvas.drawLine(box.topLeft, box.topLeft + const Offset(0, corner), paint);
    canvas.drawLine(box.topRight, box.topRight + const Offset(-corner, 0), paint);
    canvas.drawLine(box.topRight, box.topRight + const Offset(0, corner), paint);
    canvas.drawLine(box.bottomLeft, box.bottomLeft + const Offset(corner, 0), paint);
    canvas.drawLine(box.bottomLeft, box.bottomLeft + const Offset(0, -corner), paint);
    canvas.drawLine(box.bottomRight, box.bottomRight + const Offset(-corner, 0), paint);
    canvas.drawLine(box.bottomRight, box.bottomRight + const Offset(0, -corner), paint);
  }

  @override
  bool shouldRepaint(covariant _ScanGuidePainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.box != box;
}

class _ScanStatusBar extends StatelessWidget {
  const _ScanStatusBar({required this.value});

  final String? value;

  @override
  Widget build(BuildContext context) {
    final found = value != null;
    final accent = found ? const Color(0xFF7CFFB1) : Colors.white;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          children: [
            Icon(
              found ? Icons.check_circle_outline : Icons.document_scanner_outlined,
              color: accent,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    found ? 'Barcode found' : 'Waiting for barcode',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    found
                        ? value!
                        : 'Fill the guide with the bars · tip pack to cut glare · GS1-128 OK',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.75),
                          letterSpacing: found ? 0.4 : 0,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// PWA scanner: live camera (browser BarcodeDetector → zxing-wasm) plus a "Take photo"
/// mode that uses the phone's own camera app for difficult, shiny labels.
class _WebScanner extends StatefulWidget {
  const _WebScanner({required this.statusValue, required this.onBarcode});

  final String? statusValue;

  /// Called once with a validated, normalized barcode.
  final void Function(String value) onBarcode;

  @override
  State<_WebScanner> createState() => _WebScannerState();
}

class _WebScannerState extends State<_WebScanner> {
  /// A live read is accepted once the same code is seen again within this window.
  static const _confirmWindow = Duration(milliseconds: 1500);

  Object? _video;
  String? _error;
  bool _torchSupported = false;
  bool _torchOn = false;
  bool _photoBusy = false;
  bool _done = false;
  final Map<String, DateTime> _seen = {};

  @override
  void dispose() {
    WebBarcodeEngine.stop();
    super.dispose();
  }

  Future<void> _startLive() async {
    final video = _video;
    if (video == null || _done) return;
    if (!await WebBarcodeEngine.waitUntilReady()) {
      if (mounted) setState(() => _error = 'engine');
      return;
    }
    if (!mounted || _done) return;
    setState(() {
      _error = null;
      _torchOn = false;
    });
    await WebBarcodeEngine.startLive(video, onCodes: _onLiveCodes, onError: _onLiveError);
    if (!mounted) return;
    setState(() => _torchSupported = WebBarcodeEngine.torchSupported());
  }

  void _onLiveError(String code) {
    debugPrint('Web scanner camera error: $code');
    if (mounted) setState(() => _error = code);
  }

  void _onLiveCodes(List<String> raw) {
    if (_done || !mounted) return;
    final now = DateTime.now();
    for (final r in raw) {
      final value = BarcodeValidator.normalize(r);
      if (value == null) {
        debugPrint('Web scanner ignored raw="$r"');
        continue;
      }
      final previous = _seen[value];
      _seen[value] = now;
      // Two matching reads in a row filter out one-off misreads on glare.
      if (previous != null && now.difference(previous) <= _confirmWindow) {
        _finish(value);
        return;
      }
    }
  }

  void _finish(String value) {
    if (_done) return;
    _done = true;
    WebBarcodeEngine.stop();
    widget.onBarcode(value);
  }

  /// Must run synchronously from the tap so the browser lets us open the camera app.
  void _takePhoto() {
    if (_photoBusy || _done) return;
    setState(() => _photoBusy = true);
    final future = WebBarcodeEngine.decodePhoto();
    unawaited(_handlePhoto(future));
  }

  Future<void> _handlePhoto(Future<List<String>?> future) async {
    List<String>? raw;
    try {
      raw = await future;
    } catch (e) {
      debugPrint('Take photo failed: $e');
      raw = const [];
    }
    if (!mounted) return;
    setState(() => _photoBusy = false);

    if (raw != null) {
      for (final r in raw) {
        final value = BarcodeValidator.normalize(r);
        if (value != null) {
          _finish(value);
          return;
        }
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('No barcode found — tilt the pack to move the glare off the bars and try again.'),
          ),
        );
    }
    // Photo mode stopped the live camera; bring it back.
    unawaited(_startLive());
  }

  Future<void> _toggleTorch() async {
    final next = !_torchOn;
    final ok = await WebBarcodeEngine.setTorch(next);
    if (mounted && ok) setState(() => _torchOn = next);
  }

  String _errorText(String code) {
    switch (code) {
      case 'permission':
        return 'Camera access is blocked. Allow the camera for this site in your browser settings, then reload. '
            'You can still use Take photo below.';
      case 'insecure':
        return 'The camera only works on a secure (https://) connection. You can still use Take photo below.';
      case 'no-camera':
        return 'No camera was found. You can still use Take photo below.';
      case 'busy':
        return 'The camera is being used by another app. Close it and reopen this page, or use Take photo below.';
      case 'engine':
        return 'The scanner could not load. Check your connection and reload the page.';
      default:
        return 'The camera could not start. You can still use Take photo below.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              final guide = Rect.fromCenter(
                center: Offset(size.width / 2, size.height * 0.45),
                width: size.width * 0.92,
                height: size.height * 0.22,
              );
              // No Clip/Transform around the video: it freezes the preview on CanvasKit.
              return Stack(
                fit: StackFit.expand,
                children: [
                  HtmlElementView.fromTagName(
                    tagName: 'video',
                    onElementCreated: (element) {
                      _video = element;
                      unawaited(_startLive());
                    },
                  ),
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _ScanGuidePainter(
                        accent: widget.statusValue != null
                            ? const Color(0xFF7CFFB1)
                            : Colors.white.withValues(alpha: 0.85),
                        box: guide,
                      ),
                    ),
                  ),
                  if (_torchSupported && _error == null)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: IconButton.filledTonal(
                        tooltip: _torchOn ? 'Torch on' : 'Torch off',
                        onPressed: _toggleTorch,
                        icon: Icon(
                          _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
                          color: _torchOn ? Colors.amber : null,
                        ),
                      ),
                    ),
                  if (_error != null)
                    Center(
                      child: SingleChildScrollView(
                        padding: AppSpacing.paddingXl,
                        child: Container(
                          padding: AppSpacing.paddingLg,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(AppRadius.xl),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.no_photography_outlined, size: 32),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                _errorText(_error!),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              if (_error == 'busy' || (_error?.startsWith('error:') ?? false)) ...[
                                const SizedBox(height: AppSpacing.md),
                                OutlinedButton(onPressed: _startLive, child: const Text('Try again')),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        _ScanStatusBar(value: widget.statusValue),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _photoBusy || widget.statusValue != null ? null : _takePhoto,
                  icon: _photoBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.photo_camera_outlined),
                  label: Text(_photoBusy ? 'Reading photo…' : 'Take photo'),
                ),
                const SizedBox(height: 6),
                Text(
                  'Shiny label? Take a photo — tilt the pack so the glare is off the bars.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _UnsupportedPlatform extends StatelessWidget {
  const _UnsupportedPlatform({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: AppSpacing.paddingXl,
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
                Icon(Icons.phone_android, color: cs.primary, size: 34),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Mobile app required',
                  style: Theme.of(context).textTheme.titleLarge?.semiBold,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Barcode scanning uses Huawei Scan Kit on Android and iOS for reliable reads on reflective packaging. Open this app on your phone.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.withColor(cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
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
