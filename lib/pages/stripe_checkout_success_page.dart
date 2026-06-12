import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/services/stripe_checkout_service.dart';
import 'package:pwa/theme.dart';
import 'package:url_launcher/url_launcher.dart';

class StripeCheckoutSuccessPage extends StatefulWidget {
  final String sessionId;

  const StripeCheckoutSuccessPage({super.key, required this.sessionId});

  @override
  State<StripeCheckoutSuccessPage> createState() => _StripeCheckoutSuccessPageState();
}

class _StripeCheckoutSuccessPageState extends State<StripeCheckoutSuccessPage> {
  bool _loading = true;
  String? _error;
  Uri? _receiptUrl;
  Uri? _hostedInvoiceUrl;
  bool _openedOnce = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await StripeCheckoutService.getReceiptUrls(sessionId: widget.sessionId);
      if (!mounted) return;
      setState(() {
        _receiptUrl = res.receiptUrl;
        _hostedInvoiceUrl = res.hostedInvoiceUrl;
      });

      final best = _hostedInvoiceUrl ?? _receiptUrl;
      if (best != null && !_openedOnce) {
        _openedOnce = true;
        await launchUrl(best, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('StripeCheckoutSuccessPage load failed: $e');
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final best = _hostedInvoiceUrl ?? _receiptUrl;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment complete'),
        actions: [
          IconButton(
            tooltip: 'Close',
            onPressed: () => context.go(AppRoutes.cart),
            icon: Icon(Icons.close, color: cs.onSurface),
          ),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        border: Border.all(color: cs.outline.withValues(alpha: 0.18)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: cs.tertiaryContainer,
                                  borderRadius: BorderRadius.circular(AppRadius.lg),
                                  border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
                                ),
                                child: Icon(Icons.verified_outlined, color: cs.onTertiaryContainer),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(child: Text('Thanks — payment received', style: Theme.of(context).textTheme.titleLarge?.semiBold)),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            best == null
                                ? 'We’re fetching your Stripe receipt…'
                                : 'Your Stripe receipt/invoice is ready. If it didn’t open automatically, you can open it again below.',
                            style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            Text('Error: $_error', style: Theme.of(context).textTheme.bodySmall?.withColor(cs.error)),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: best == null
                                      ? null
                                      : () async {
                                          await launchUrl(best, mode: LaunchMode.externalApplication);
                                        },
                                  icon: Icon(Icons.open_in_new, color: cs.onPrimary),
                                  label: Text('Open Stripe invoice', style: TextStyle(color: cs.onPrimary)),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _load,
                                  icon: Icon(Icons.refresh, color: cs.onSurface),
                                  label: Text('Refresh', style: TextStyle(color: cs.onSurface)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          OutlinedButton.icon(
                            onPressed: () => context.go(AppRoutes.cart),
                            icon: Icon(Icons.shopping_cart_outlined, color: cs.onSurface),
                            label: Text('Back to Cart', style: TextStyle(color: cs.onSurface)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_loading)
            Positioned.fill(
              child: ColoredBox(
                color: cs.surface.withValues(alpha: 0.65),
                child: const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5))),
              ),
            ),
        ],
      ),
    );
  }
}
