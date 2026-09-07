import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scankit/flutter_scankit.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/components/app_header.dart';
import 'package:pwa/nav.dart';
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
          ? _UnsupportedPlatform(
              onClose: _leaveToCart,
            )
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

class _UnsupportedPlatform extends StatelessWidget {
  const _UnsupportedPlatform({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
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
