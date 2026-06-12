import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/services/invoice_webhook_service.dart';
import 'package:pwa/services/pending_invoice_storage.dart';
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
  bool _postingInvoice = false;
  bool _postedInvoice = false;
  String? _createdInvoiceId;

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

      // After payment completion, create the invoice via Make using the locally
      // saved cart + invoice draft payload.
      await _postPendingInvoiceIfNeeded();
    } catch (e) {
      debugPrint('StripeCheckoutSuccessPage load failed: $e');
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _postPendingInvoiceIfNeeded() async {
    if (_postingInvoice || _postedInvoice) return;

    final payload = await PendingInvoiceStorage.load();
    if (payload == null) {
      debugPrint('StripeCheckoutSuccessPage: no pending invoice payload found.');
      return;
    }

    setState(() => _postingInvoice = true);
    try {
      final res = await InvoiceWebhookService.submitInvoicePayload(payload, markPaid: true);
      final createdInvoiceId = res.body;
      if (createdInvoiceId == null || createdInvoiceId.toString().trim().isEmpty) {
        throw Exception('Invoice webhook succeeded, but no invoice id was returned.');
      }
      await PendingInvoiceStorage.clear();
      _postedInvoice = true;
      _createdInvoiceId = createdInvoiceId.toString().trim();
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      debugPrint('StripeCheckoutSuccessPage: posting pending invoice failed: $e');
      if (mounted) {
        setState(() => _error = 'Failed to create invoice after payment: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _postingInvoice = false);
    }
  }

  Future<void> _openCreatedInvoice() async {
    // Ensure we have an invoice id (try to post if it hasn't happened yet).
    if (_createdInvoiceId == null) {
      await _postPendingInvoiceIfNeeded();
    }
    final id = _createdInvoiceId?.trim() ?? '';
    if (!mounted) return;
    if (id.isEmpty) {
      setState(() => _error = _error ?? 'Invoice is not ready yet. Please wait a moment and try again.');
      return;
    }
    context.go(AppRoutes.invoiceSuccess(id));
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
            onPressed: () => context.go(AppRoutes.invoice),
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
                          Center(
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              spacing: AppSpacing.md,
                              runSpacing: AppSpacing.sm,
                              children: [
                                FilledButton.icon(
                                  onPressed: best == null
                                      ? null
                                      : () async {
                                          await launchUrl(best, mode: LaunchMode.externalApplication);
                                        },
                                  icon: Icon(Icons.open_in_new, color: cs.onPrimary),
                                  label: Text('Open Stripe invoice', style: TextStyle(color: cs.onPrimary)),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _postingInvoice ? null : _openCreatedInvoice,
                                  icon: Icon(Icons.receipt_long_outlined, color: cs.onSurface),
                                  label: Text('Open Invoice', style: TextStyle(color: cs.onSurface)),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => context.go(AppRoutes.invoice),
                                  icon: Icon(Icons.request_quote_outlined, color: cs.onSurface),
                                  label: Text('Back to Invoice', style: TextStyle(color: cs.onSurface)),
                                ),
                              ],
                            ),
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
