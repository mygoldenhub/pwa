import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/models/cart_item.dart';
import 'package:pwa/components/new_invoice_sheet.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/theme.dart';

class InvoiceSuccessPage extends StatelessWidget {
  final Object? draft;
  final Object? webhook;
  final Object? cartItems;

  const InvoiceSuccessPage({super.key, this.draft, this.webhook, this.cartItems});

  ({double subtotal, double gst, double amountDue}) _computeTotals({required double total, required LineAmountType lineAmountType}) {
    // Interpret "total" as the user-entered budget value.
    // - Exclusive: total is subtotal; GST is added.
    // - Inclusive: total already includes GST.
    // - NoTax: GST is 0.
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
    String fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
          // Unit prices are already tax-inclusive.
          return base;
        case LineAmountType.exclusive:
          return base * 1.1;
      }
    }

    final rows = items
        .where((e) => e.productName.trim().isNotEmpty)
        .map(
          (e) {
            final base = ((e.unitPriceCents ?? 0) * e.quantity) / 100.0;
            return (reference: e.productName.trim(), amountWithTax: lineTotalWithTax(base));
          },
        )
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
              Expanded(child: Text('Budget summary', style: Theme.of(context).textTheme.titleMedium?.semiBold)),
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
                      Text(
                        '${draft.currencyCode} ${money(r.amountWithTax)}',
                        style: Theme.of(context).textTheme.bodyMedium?.semiBold,
                      ),
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          Container(height: 1, color: cs.outline.withValues(alpha: 0.12)),
          const SizedBox(height: 12),
          _CompactAmountRow(description: 'Budget', value: '${draft.currencyCode} ${money(total)}'),
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final typedDraft = (draft is InvoiceDraft) ? (draft as InvoiceDraft) : null;
    final typedCartItems = (cartItems is List<CartItem>) ? (cartItems as List<CartItem>) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Success'), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.paddingLg,
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
                    const SizedBox(height: 14),
                    if (typedDraft != null)
                      _buildBudgetSummary(
                        context,
                        draft: typedDraft,
                        items: typedCartItems ?? const <CartItem>[],
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        // Navigate straight to the Invoice page (no extra payload)
                        // so the user lands on the normal invoice list view.
                        onPressed: () => context.go(AppRoutes.invoice),
                        icon: Icon(Icons.open_in_new, color: cs.onPrimary),
                        label: Text('Goto Invoice', style: TextStyle(color: cs.onPrimary)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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

/// A compact row that matches the visual weight of the Line items rows:
/// label on the left, and a bold currency amount on the right.
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
