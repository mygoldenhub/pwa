import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/components/app_header.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/theme.dart';
import 'package:pwa/utils/barcode_normalize.dart';

/// Waits for input from a USB / Bluetooth barcode scanner (keyboard wedge).
class BarcodeHardwareScannerPage extends StatefulWidget {
  const BarcodeHardwareScannerPage({super.key});

  @override
  State<BarcodeHardwareScannerPage> createState() => _BarcodeHardwareScannerPageState();
}

class _BarcodeHardwareScannerPageState extends State<BarcodeHardwareScannerPage> with WidgetsBindingObserver {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _didReturn = false;
  String? _lastScanPreview;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inputController.addListener(_onInputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestFocus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inputController
      ..removeListener(_onInputChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _requestFocus();
    }
  }

  void _requestFocus() {
    if (!mounted || _didReturn) return;
    _focusNode.requestFocus();
  }

  void _goToCart() {
    if (_didReturn) return;
    _didReturn = true;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.cart);
    }
  }

  void _onInputChanged() {
    final raw = _inputController.text;
    if (raw.contains('\n') || raw.contains('\r')) {
      final value = raw.replaceAll('\r', '').replaceAll('\n', '').trim();
      _inputController.clear();
      if (value.isNotEmpty) {
        _acceptScan(value);
      }
    }
  }

  void _acceptScan(String raw) {
    if (_didReturn) return;
    final value = BarcodeNormalize.primary(raw) ?? raw.trim();
    if (value.isEmpty) return;

    debugPrint('Hardware scanner accepted: $raw -> $value');
    setState(() => _lastScanPreview = value);
    _didReturn = true;
    HapticFeedback.mediumImpact();
    context.go(AppRoutes.barcodeResult(value));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppImpactHeader(
        title: 'Barcode scanner',
        actions: [
          IconButton(
            tooltip: 'Back to cart',
            onPressed: _goToCart,
            icon: Icon(Icons.close, color: cs.onSurface),
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _requestFocus,
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: AppSpacing.paddingLg,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: CircularProgressIndicator(strokeWidth: 3, color: cs.primary),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'Waiting for barcode scan…',
                          style: Theme.of(context).textTheme.titleLarge?.semiBold,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Use your barcode scanner to scan a product label. '
                          'The scanner should be connected and ready.',
                          style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        if (kDebugMode) ...[
                          const SizedBox(height: AppSpacing.lg),
                          Container(
                            width: double.infinity,
                            padding: AppSpacing.paddingMd,
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
                            ),
                            child: Text(
                              'No scanner? Click this page, type a barcode on your keyboard '
                              '(e.g. 9315021121551), then press Enter.',
                              style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        if ((_lastScanPreview ?? '').isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            _lastScanPreview!,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // Hidden input captures keyboard-wedge scanner keystrokes.
              Positioned(
                left: 0,
                top: 0,
                width: 1,
                height: 1,
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: _inputController,
                    focusNode: _focusNode,
                    autofocus: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    showCursor: false,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: _acceptScan,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
