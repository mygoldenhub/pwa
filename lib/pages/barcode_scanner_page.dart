import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pwa/theme.dart';

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  final MobileScannerController _controller = MobileScannerController(autoStart: true);
  bool _didReturn = false;
  String? _lastValue;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _returnBarcode(String value) {
    if (_didReturn) return;
    _didReturn = true;
    context.pop<String>(value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan barcode'),
        actions: [
          IconButton(
            tooltip: 'Toggle torch',
            onPressed: () async {
              try {
                await _controller.toggleTorch();
              } catch (e) {
                debugPrint('Torch toggle failed: $e');
              }
            },
            icon: const Icon(Icons.flashlight_on),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_didReturn) return;
              final barcodes = capture.barcodes;
              if (barcodes.isEmpty) return;
              final raw = barcodes.first.rawValue;
              if (raw == null || raw.trim().isEmpty) return;

              final value = raw.trim();
              if (_lastValue == value) return;
              _lastValue = value;
              _returnBarcode(value);
            },
            errorBuilder: (context, error) {
              debugPrint('MobileScanner error: $error');
              return _ScannerErrorState(error: error);
            },
          ),
          const _ScannerOverlay(),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: AppSpacing.paddingLg,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Align the barcode inside the frame',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => context.pop<String?>(null),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                            ),
                            icon: const Icon(Icons.edit, color: Colors.white),
                            label: const Text('Enter manually'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              try {
                                await _controller.switchCamera();
                              } catch (e) {
                                debugPrint('Switch camera failed: $e');
                              }
                            },
                            style: FilledButton.styleFrom(backgroundColor: cs.primary),
                            icon: Icon(Icons.cameraswitch, color: cs.onPrimary),
                            label: Text('Flip', style: TextStyle(color: cs.onPrimary)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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
  const _ScannerErrorState({required this.error});

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
                  'Please allow camera access, or enter the barcode manually.',
                  style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => context.pop<String?>(null),
                    icon: Icon(Icons.edit, color: cs.onPrimary),
                    label: Text('Enter manually', style: TextStyle(color: cs.onPrimary)),
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

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final cutoutWidth = size.width * 0.72;
          final cutoutHeight = size.height * 0.24;
          final cutout = Rect.fromCenter(
            center: size.center(Offset.zero),
            width: cutoutWidth.clamp(220, 520),
            height: cutoutHeight.clamp(120, 240),
          );
          return CustomPaint(painter: _ScannerOverlayPainter(cutout: cutout));
        },
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final Rect cutout;
  _ScannerOverlayPainter({required this.cutout});

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final border = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final full = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRRect(RRect.fromRectAndRadius(cutout, const Radius.circular(24)));
    final overlay = Path.combine(PathOperation.difference, full, hole);
    canvas.drawPath(overlay, scrim);
    canvas.drawRRect(RRect.fromRectAndRadius(cutout, const Radius.circular(24)), border);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) => oldDelegate.cutout != cutout;
}
