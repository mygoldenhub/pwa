import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/models/cart_item.dart';
import 'package:pwa/models/xero_invoice.dart';
import 'package:pwa/components/new_invoice_sheet.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/services/xero_invoice_service.dart';
import 'package:pwa/theme.dart';

class InvoiceSuccessPage extends StatefulWidget {
  /// Invoice id encoded in the URL: `/app/invoice/success/:invoiceId`
  ///
  /// When present, this page can reload invoice data after browser refresh.
  final String? invoiceId;

  /// Legacy extras (kept for existing UI and backwards compatibility).
  final Object? draft;
  final Object? webhook;
  final Object? cartItems;

  const InvoiceSuccessPage({super.key, required this.invoiceId, this.draft, this.webhook, this.cartItems});

  @override
  State<InvoiceSuccessPage> createState() => _InvoiceSuccessPageState();
}

class _InvoiceSuccessPageState extends State<InvoiceSuccessPage> {
  late final Future<XeroInvoice?> _invoiceFuture;

  @override
  void initState() {
    super.initState();
    final id = widget.invoiceId?.trim();
    _invoiceFuture = (id == null || id.isEmpty) ? Future<XeroInvoice?>.value(null) : _loadInvoice(id);
  }

  Future<XeroInvoice?> _loadInvoice(String invoiceId) async {
    try {
      return await XeroInvoiceService.getMyInvoiceDetails(invoiceId: invoiceId);
    } catch (e) {
      debugPrint('InvoiceSuccessPage: failed to load invoice $invoiceId: $e');
      rethrow;
    }
  }

  ({double subtotal, double gst, double amountDue}) _computeTotals({required double total, required LineAmountType lineAmountType}) {
    switch (lineAmountType) {
      case LineAmountType.noTax:
        return (subtotal: total, gst: 0.0, amountDue: total);
      case LineAmountType.inclusive:
        final subtotal = total / 1.1;
        final gst = total - subtotal;
        return (subtotal: subtotal, gst: gst, amountDue: total);
      case LineAmountType.exclusive:
        final gst = total * 0.1;
        return (subtotal: total, gst: gst, amountDue: total + gst);
    }
  }

  Widget _buildBudgetSummary(BuildContext context, {required InvoiceDraft draft, required List<CartItem> items}) {
    final cs = Theme.of(context).colorScheme;
    String fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year.toString().padLeft(4, '0')}';

    final total = draft.totalBudgetCents / 100.0;
    final totals = _computeTotals(total: total, lineAmountType: draft.lineAmountType);
    String money(double v) => v.toStringAsFixed(2);
    final taxLabel = switch (draft.lineAmountType) {
      LineAmountType.noTax => 'Tax',
      _ => 'GST 10%'
    };

    double lineTotalWithTax(double base) {
      switch (draft.lineAmountType) {
        case LineAmountType.noTax:
          return base;
        case LineAmountType.inclusive:
          return base;
        case LineAmountType.exclusive:
          return base * 1.1;
      }
    }

    final rows = items
        .where((e) => e.productName.trim().isNotEmpty)
        .map((e) {
          final base = ((e.unitPriceCents ?? 0) * e.quantity) / 100.0;
          return (reference: e.productName.trim(), amountWithTax: lineTotalWithTax(base));
        })
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Invoice summary', style: Theme.of(context).textTheme.titleMedium?.semiBold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(999)),
                child: Text(
                  draft.currencyCode,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _MetaRow(icon: Icons.tag_outlined, label: 'Reference', value: draft.reference.isEmpty ? '-' : draft.reference),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _MetaRow(icon: Icons.event, label: 'Date', value: fmt(draft.date))),
              const SizedBox(width: 12),
              Expanded(child: _MetaRow(icon: Icons.event_available, label: 'Due date', value: fmt(draft.dueDate))),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: Text('Line items', style: Theme.of(context).textTheme.titleSmall?.semiBold)),
              if (rows.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    '${rows.length}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onSecondaryContainer, fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Text('Reference', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700))),
              const SizedBox(width: 12),
              Text('Amount', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Text('No line items', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: rows.length,
                separatorBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Container(height: 1, color: cs.outline.withValues(alpha: 0.10)),
                ),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.reference,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('${draft.currencyCode} ${money(r.amountWithTax)}', style: Theme.of(context).textTheme.bodyMedium?.semiBold),
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          Container(height: 1, color: cs.outline.withValues(alpha: 0.12)),
          const SizedBox(height: 12),
          _CompactAmountRow(description: 'Total', value: '${draft.currencyCode} ${money(total)}'),
          const SizedBox(height: 8),
          _CompactAmountRow(description: taxLabel, value: '${draft.currencyCode} ${money(totals.gst)}'),
          const SizedBox(height: 10),
          Container(height: 1, color: cs.outline.withValues(alpha: 0.12)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Text('Amount Due', style: Theme.of(context).textTheme.titleMedium?.semiBold)),
              Text(
                '${draft.currencyCode} ${money(totals.amountDue)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: cs.onSurface),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceDetailsCard(BuildContext context, XeroInvoice inv) {
    final cs = Theme.of(context).colorScheme;
    String money(double? v) => (v ?? 0).toStringAsFixed(2);

    final currency = (inv.currencyCode?.trim().isNotEmpty ?? false) ? inv.currencyCode!.trim() : 'AUD';
    final title = (inv.invoiceNum?.trim().isNotEmpty ?? false) ? inv.invoiceNum!.trim() : 'Invoice';
    final reference = inv.reference?.trim().isNotEmpty ?? false ? inv.reference!.trim() : '-';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(AppRadius.lg)),
                child: Icon(Icons.receipt_long, color: cs.onTertiaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.semiBold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(999)),
                child: Text(currency, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onPrimaryContainer, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MetaRow(icon: Icons.confirmation_number_outlined, label: 'Invoice ID', value: inv.invoiceId),
          const SizedBox(height: 8),
          _MetaRow(icon: Icons.tag_outlined, label: 'Reference', value: reference),
          const SizedBox(height: 12),
          Container(height: 1, color: cs.outline.withValues(alpha: 0.12)),
          const SizedBox(height: 12),
          _CompactAmountRow(description: 'Total', value: '$currency ${money(inv.total)}'),
          const SizedBox(height: 8),
          _CompactAmountRow(description: 'Paid', value: '$currency ${money(inv.amountPaid)}'),
          const SizedBox(height: 8),
          _CompactAmountRow(description: 'Due', value: '$currency ${money(inv.amountDue)}'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final typedDraft = (widget.draft is InvoiceDraft) ? (widget.draft as InvoiceDraft) : null;
    final typedCartItems = (widget.cartItems is List<CartItem>) ? (widget.cartItems as List<CartItem>) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Success'), centerTitle: true, automaticallyImplyLeading: false),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: AppSpacing.paddingLg,
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        color: cs.surface,
                        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(AppRadius.lg)),
                                child: Icon(Icons.check_rounded, size: 26, color: cs.onPrimaryContainer),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text('Invoice created', style: Theme.of(context).textTheme.titleLarge?.semiBold)),
                            ],
                          ),

                          if (widget.invoiceId != null && widget.invoiceId!.trim().isNotEmpty) ...[
                            const SizedBox(height: 14),
                            FutureBuilder<XeroInvoice?>(
                              future: _invoiceFuture,
                              builder: (context, snap) {
                                if (snap.connectionState == ConnectionState.waiting) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 18),
                                    child: Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5))),
                                  );
                                }
                                if (snap.hasError) {
                                  return _InlineErrorCard(
                                    title: 'Couldn\'t load invoice',
                                    subtitle: snap.error.toString(),
                                  );
                                }
                                final inv = snap.data;
                                if (inv == null) {
                                  return const _InlineErrorCard(title: 'Invoice not found', subtitle: 'This invoice could not be loaded.');
                                }
                                return _buildInvoiceDetailsCard(context, inv);
                              },
                            ),
                          ],

                          if (typedDraft != null) ...[
                            const SizedBox(height: 14),
                            _buildBudgetSummary(context, draft: typedDraft, items: typedCartItems ?? const <CartItem>[]),
                          ],

                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => context.go(AppRoutes.invoice),
                              icon: Icon(Icons.open_in_new, color: cs.onPrimary),
                              label: Text('Open invoices', style: TextStyle(color: cs.onPrimary)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InlineErrorCard extends StatelessWidget {
  final String title;
  final String subtitle;
  const _InlineErrorCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: cs.error.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.onErrorContainer, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onErrorContainer)),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetaRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.semiBold),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompactAmountRow extends StatelessWidget {
  final String description;
  final String value;

  const _CompactAmountRow({required this.description, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: 12),
        Text(value, style: Theme.of(context).textTheme.bodyMedium?.semiBold),
      ],
    );
  }
}
