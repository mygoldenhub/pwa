import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/models/xero_invoice.dart';
import 'package:pwa/services/invoice_webhook_service.dart';
import 'package:pwa/services/pending_invoice_payment_storage.dart';
import 'package:pwa/services/stripe_checkout_service.dart';
import 'package:pwa/services/xero_invoice_service.dart';
import 'package:pwa/theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// A centered modal dialog that displays invoice details.
///
/// This widget performs a dynamic fetch to load heavy fields like `line_items`
/// and `payments` (payment history).
class InvoiceDetailsDialog extends StatefulWidget {
  final XeroInvoice invoice;
  final String budgetText;
  final Widget statusPill;

  const InvoiceDetailsDialog({super.key, required this.invoice, required this.budgetText, required this.statusPill});

  @override
  State<InvoiceDetailsDialog> createState() => _InvoiceDetailsDialogState();
}

class _InvoiceDetailsDialogState extends State<InvoiceDetailsDialog> {
  bool _isLoading = true;
  Object? _error;
  XeroInvoice? _details;

  bool _isStartingCheckout = false;

  Map<String, dynamic> _buildInvoicePaymentPayload(XeroInvoice invoice) {
    final date = invoice.date ?? DateTime.now();
    final dueDate = invoice.dueDate ?? date;
    final contactId = (invoice.contactId ?? '').trim();

    dynamic accountCodeOf(Map<String, dynamic> li) {
      final raw = (li['account_code'] ?? li['AccountCode'] ?? li['accountCode'])?.toString().trim();
      if (raw == null || raw.isEmpty) return null;
      return int.tryParse(raw) ?? raw;
    }

    String lineItemTitle(Map<String, dynamic> li) {
      final v = (li['description'] ?? li['Description'] ?? li['name'] ?? li['ItemCode'] ?? li['item_code'] ?? li['reference'])?.toString().trim();
      return (v == null || v.isEmpty) ? 'Line item' : v;
    }

    final inv = invoice; // naming clarity
    final products = inv.lineItems.map((li) {
      final qty = _asDouble(li['quantity'] ?? li['Quantity']) ?? 1;
      final unit = _asDouble(li['unit_amount'] ?? li['UnitAmount'] ?? li['unitAmount']);
      final total = _asDouble(li['line_amount'] ?? li['LineAmount'] ?? li['lineAmount']);
      final effectiveUnit = (unit != null && unit > 0)
          ? unit
          : (total != null && qty > 0)
              ? total / qty
              : 0.0;
      return <String, dynamic>{
        'description': li['description'] ?? li['Description'] ?? lineItemTitle(li),
        'quantity': qty,
        'unit amount': effectiveUnit,
        'item': lineItemTitle(li),
        'account code': accountCodeOf(li),
      };
    }).toList();

    return <String, dynamic>{
      'invoice_id': inv.invoiceId,
      'reference': (inv.reference ?? inv.invoiceNum ?? '').toString(),
      'currency_code': (inv.currencyCode ?? '').toString(),
      'currency_rate': inv.currencyRate ?? 1.0,
      'line_amount_type': (inv.lineAmountTypes ?? '').toString(),
      'date': InvoiceWebhookService.fmtDate(date),
      'due_date': InvoiceWebhookService.fmtDate(dueDate),
      'contactID': contactId,
      'products': products,
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final res = await XeroInvoiceService.getMyInvoiceDetails(invoiceId: widget.invoice.invoiceId);
      if (!mounted) return;
      setState(() => _details = res);
    } catch (e) {
      debugPrint('InvoiceDetailsDialog: failed to load details: $e');
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  String _fmtDateTimeLocal(DateTime? d) {
    if (d == null) return '-';
    final local = d.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$day $hh:$mm';
  }

  DateTime? _parsePaymentDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  String _money(num? v, {String? currencyCode}) {
    if (v == null) return '-';
    final amount = v.toDouble().toStringAsFixed(2);
    final c = (currencyCode ?? '').trim();
    return c.isEmpty ? amount : '$amount $c';
  }

  String _lineItemTitle(Map<String, dynamic> li) {
    final v = (li['description'] ?? li['Description'] ?? li['name'] ?? li['ItemCode'] ?? li['item_code'] ?? li['reference'])?.toString().trim();
    return (v == null || v.isEmpty) ? 'Line item' : v;
  }

  String _qtyText(double qty) {
    if (qty % 1 == 0) return qty.toInt().toString();
    // Keep to a reasonable precision for fractional quantities.
    return qty.toStringAsFixed(2);
  }

  String _unitTimesQtyText({required double unitAmount, required double quantity}) => '${unitAmount.toStringAsFixed(2)} × ${_qtyText(quantity)}';

  bool _isInvoiceUnpaid(XeroInvoice invoice) {
    final s = (invoice.status ?? '').trim().toUpperCase();
    if (s.isEmpty) return false;
    return s != 'PAID';
  }

  Future<void> _startStripeCheckoutForInvoice(XeroInvoice invoice) async {
    if (_isStartingCheckout) return;
    setState(() => _isStartingCheckout = true);
    final cs = Theme.of(context).colorScheme;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: cs.scrim.withValues(alpha: 0.52),
      builder: (context) => const Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.6))),
      ),
    );

    try {
      // Requirement: persist invoice details before leaving to Stripe Checkout.
      await PendingInvoicePaymentStorage.save(_buildInvoicePaymentPayload(invoice));

      final currency = (invoice.currencyCode ?? '').trim().isEmpty ? 'aud' : invoice.currencyCode!.trim();
      final checkoutUrl = await StripeCheckoutService.createHostedCheckoutUrl(
        currency: currency,
        reference: (invoice.reference ?? invoice.invoiceNum ?? '').trim(),
        invoiceId: invoice.invoiceId,
        lineItems: StripeCheckoutService.buildLineItemsFromInvoice(invoice),
        customerEmail: null,
      );

      if (!mounted) return;
      context.pop(); // close loading

      final ok = await launchUrl(checkoutUrl, mode: LaunchMode.externalApplication);
      if (!ok) throw 'Could not open Stripe Checkout.';
    } catch (e) {
      debugPrint('InvoiceDetailsDialog: startStripeCheckout failed: $e');
      if (mounted) {
        context.pop(); // close loading
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              showCloseIcon: true,
              margin: const EdgeInsets.all(AppSpacing.lg),
              content: Text('Failed to start Stripe Checkout: ${e.toString()}'),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _isStartingCheckout = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final invoice = _details ?? widget.invoice;
    final isUnpaid = _isInvoiceUnpaid(invoice);

    final invoiceNum = (invoice.invoiceNum ?? '').trim();
    final title = invoiceNum.isNotEmpty ? invoiceNum : 'Invoice';
    final reference = (invoice.reference ?? '').trim();
    final updated = _fmtDateTimeLocal(invoice.updatedDateUtc ?? invoice.date);
    final due = _fmtDateTimeLocal(invoice.dueDate).split(' ').first;

    final lineItems = invoice.lineItems;
    final payments = invoice.payments;

    final dialog = Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 620, maxHeight: MediaQuery.sizeOf(context).height * 0.80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.sm, AppSpacing.md),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(bottom: BorderSide(color: cs.outline.withValues(alpha: 0.10))),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: tt.titleLarge?.semiBold, softWrap: true),
                        const SizedBox(height: 4),
                        Text(updated, style: tt.bodySmall?.withColor(cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      widget.statusPill,
                      if (isUnpaid) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 36,
                          child: FilledButton.icon(
                            onPressed: (_isLoading || _error != null || _isStartingCheckout) ? null : () => _startStripeCheckoutForInvoice(invoice),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                            ),
                            icon: Icon(Icons.credit_card, color: cs.onPrimary, size: 18),
                            label: Text('Pay now', style: tt.labelLarge?.withColor(cs.onPrimary)),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(
                    onPressed: context.pop,
                    icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: AppSpacing.paddingLg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SheetCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SheetKvRow(label: 'Reference', value: reference.isEmpty ? '-' : reference),
                          const SizedBox(height: AppSpacing.sm),
                          _SheetKvRow(label: 'Budget', value: widget.budgetText),
                          const SizedBox(height: AppSpacing.sm),
                          _SheetKvRow(label: 'Due', value: due),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_isLoading)
                      _LoadingBlock()
                    else if (_error != null)
                      _ErrorBlock(message: _error.toString(), onRetry: _load)
                    else ...[
                      if (lineItems.isNotEmpty) ...[
                        Text('Line items', style: tt.titleMedium?.semiBold),
                        const SizedBox(height: AppSpacing.sm),
                        for (final li in lineItems) ...[
                          Builder(
                            builder: (context) {
                              final qty = _asDouble(li['quantity'] ?? li['Quantity']);
                              final unit = _asDouble(li['unit_amount'] ?? li['UnitAmount'] ?? li['unitAmount']);
                              final total = _asDouble(li['line_amount'] ?? li['LineAmount'] ?? li['lineAmount']) ?? _computeLineAmount(li);
                              final unitTimesQty = (qty != null && unit != null) ? _unitTimesQtyText(unitAmount: unit, quantity: qty) : null;

                              return _SheetCard(
                                padding: AppSpacing.paddingMd,
                                child: _LineItemRow(
                                  title: _lineItemTitle(li),
                                  unitTimesQtyText: unitTimesQty,
                                  totalText: _money(total, currencyCode: invoice.currencyCode),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      if (payments.isNotEmpty) ...[
                        Text('Payment history', style: tt.titleMedium?.semiBold),
                        const SizedBox(height: AppSpacing.sm),
                        for (final p in payments) ...[
                          _SheetCard(
                            padding: AppSpacing.paddingMd,
                            child: _PaymentRow(
                              dateText: _fmtDateTimeLocal(_parsePaymentDate(p['date'] ?? p['data'] ?? p['Date'])).split(' ').first,
                              reference: (p['reference'] ?? p['Reference'])?.toString().trim(),
                              amountText: _money(_asDouble(p['amount'] ?? p['Amount']), currencyCode: invoice.currencyCode),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                      ] else ...[
                        Text('Payment history', style: tt.titleMedium?.semiBold),
                        const SizedBox(height: AppSpacing.sm),
                        Text('No payments recorded.', style: tt.bodySmall?.withColor(cs.onSurfaceVariant)),
                      ],
                    ],
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
      backgroundColor: Colors.transparent,
      elevation: 0,
      alignment: Alignment.center,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 22, offset: const Offset(0, 14))],
        ),
        child: dialog,
      ),
    );
  }

  double? _computeLineAmount(Map<String, dynamic> li) {
    final qty = _asDouble(li['quantity'] ?? li['Quantity']);
    final unit = _asDouble(li['unit_amount'] ?? li['UnitAmount'] ?? li['unitAmount']);
    if (qty == null || unit == null) return null;
    return qty * unit;
  }
}

class _SheetCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _SheetCard({required this.child, this.padding = AppSpacing.paddingLg});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: child,
    );
  }
}

class _SheetKvRow extends StatelessWidget {
  final String label;
  final String value;

  const _SheetKvRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: tt.labelSmall?.withColor(cs.onSurfaceVariant))),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          flex: 2,
          child: Text(value, style: tt.bodyMedium?.semiBold, softWrap: true, textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return _SheetCard(
      padding: AppSpacing.paddingMd,
      child: Row(
        children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text('Loading details…', style: tt.bodyMedium?.withColor(cs.onSurfaceVariant))),
        ],
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBlock({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return _SheetCard(
      padding: AppSpacing.paddingMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Could not load invoice details', style: tt.titleSmall?.semiBold),
          const SizedBox(height: 6),
          Text(message, style: tt.bodySmall?.withColor(cs.onSurfaceVariant), maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh, color: cs.primary),
              label: Text('Retry', style: tt.labelLarge?.withColor(cs.primary)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineItemRow extends StatelessWidget {
  final String title;
  final String? unitTimesQtyText;
  final String totalText;

  const _LineItemRow({required this.title, required this.totalText, this.unitTimesQtyText});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: tt.bodyMedium?.semiBold, softWrap: true),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 140),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  (unitTimesQtyText ?? '-'),
                  style: tt.labelSmall?.withColor(cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  totalText,
                  style: tt.bodyMedium?.semiBold,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final String dateText;
  final String? reference;
  final String amountText;

  const _PaymentRow({required this.dateText, required this.amountText, this.reference});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final ref = (reference ?? '').trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(dateText, style: tt.bodyMedium?.semiBold, softWrap: true),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 160),
          child: SizedBox(
            height: 44,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    ref.isEmpty ? '-' : ref,
                    style: tt.labelSmall?.withColor(cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                    softWrap: true,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    amountText,
                    style: tt.bodyMedium?.semiBold,
                    textAlign: TextAlign.center,
                    softWrap: true,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
