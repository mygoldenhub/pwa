import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/models/xero_invoice.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/services/xero_invoice_service.dart';
import 'package:pwa/theme.dart';

class InvoiceSuccessPage extends StatefulWidget {
  final String invoiceId;

  const InvoiceSuccessPage({
    super.key,
    required this.invoiceId,
  });

  @override
  State<InvoiceSuccessPage> createState() => _InvoiceSuccessPageState();
}

class _InvoiceSuccessPageState extends State<InvoiceSuccessPage> {
  late final Future<XeroInvoice?> _invoiceFuture;

  @override
  void initState() {
    super.initState();
    final id = widget.invoiceId.trim();
    debugPrint('InvoiceSuccessPage invoiceId: $id');
    _invoiceFuture =
        id.isEmpty ? Future<XeroInvoice?>.value(null) : _loadInvoice(id);
  }

  Future<XeroInvoice?> _loadInvoice(String invoiceId) async {
    try {
      return await XeroInvoiceService.getMyInvoiceDetails(
        invoiceId: invoiceId,
      );
    } catch (e) {
      debugPrint('InvoiceSuccessPage: failed to load invoice $invoiceId: $e');
      rethrow;
    }
  }

  T? _safe<T>(T Function() reader) {
    try {
      return reader();
    } catch (_) {
      return null;
    }
  }

  dynamic _mapValue(dynamic source, String key) {
    if (source is Map) {
      return source[key];
    }
    return null;
  }

  dynamic _firstValue(List<dynamic Function()> readers) {
    for (final reader in readers) {
      try {
        final value = reader();
        if (value != null) return value;
      } catch (_) {}
    }
    return null;
  }

  String _firstText(
    List<dynamic Function()> readers, {
    String fallback = '-',
  }) {
    for (final reader in readers) {
      try {
        final value = reader();
        final text = value?.toString().trim() ?? '';
        if (text.isNotEmpty) return text;
      } catch (_) {}
    }
    return fallback;
  }

  double _asDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();

    final text = value.toString().trim().replaceAll(',', '');
    return double.tryParse(text) ?? 0.0;
  }

  String _formatMoney(double value) => value.toStringAsFixed(2);

  String _formatDate(dynamic value) {
    if (value == null) return '-';

    DateTime? date;

    if (value is DateTime) {
      date = value;
    } else {
      final raw = value.toString().trim();
      if (raw.isEmpty) return '-';

      date = DateTime.tryParse(raw);
      if (date == null) return raw;
    }

    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year.toString().padLeft(4, '0')}';
  }

  List<dynamic> _extractRawLineItems(dynamic invoice) {
    final raw = _firstValue([
      () => _safe(() => invoice.lineItems),
      () => _mapValue(invoice, 'lineItems'),
      () => _safe(() => invoice.items),
      () => _mapValue(invoice, 'items'),
    ]);

    return raw is List ? raw : const [];
  }

  String _lineItemReference(dynamic item) {
    return _firstText([
      () => _safe(() => item.description),
      () => _mapValue(item, 'description'),
      () => _safe(() => item.productName),
      () => _mapValue(item, 'productName'),
      () => _safe(() => item.reference),
      () => _mapValue(item, 'reference'),
      () => _safe(() => item.itemCode),
      () => _mapValue(item, 'itemCode'),
      () => _safe(() => item.name),
      () => _mapValue(item, 'name'),
      () => _safe(() => item.title),
      () => _mapValue(item, 'title'),
    ]);
  }

  double _lineItemAmount(dynamic item) {
    final directAmount = _asDouble(_firstValue([
      () => _safe(() => item.lineAmount),
      () => _mapValue(item, 'line_amount'),
      () => _safe(() => item.amount),
      () => _mapValue(item, 'amount'),
      () => _safe(() => item.total),
      () => _mapValue(item, 'total'),
      () => _safe(() => item.lineTotal),
      () => _mapValue(item, 'lineTotal'),
    ]));

    final taxAmount = _asDouble(_firstValue([
      () => _safe(() => item.taxAmount),
      () => _mapValue(item, 'tax_amount'),
      () => _safe(() => item.tax),
      () => _mapValue(item, 'tax'),
      () => _safe(() => item.gst),
      () => _mapValue(item, 'gst'),
    ]));

    final quantity = _asDouble(_firstValue([
      () => _safe(() => item.quantity),
      () => _mapValue(item, 'quantity'),
      () => _safe(() => item.qty),
      () => _mapValue(item, 'qty'),
    ]));

    final unitAmount = _asDouble(_firstValue([
      () => _safe(() => item.unitAmount),
      () => _mapValue(item, 'unit_amount'),
      () => _safe(() => item.unitPrice),
      () => _mapValue(item, 'unitPrice'),
      () => _safe(() => item.price),
      () => _mapValue(item, 'price'),
    ]));

    final computedBase = unitAmount * (quantity > 0 ? quantity : 1);

    double baseAmount;
    if (directAmount > 0) {
      baseAmount = directAmount;
    } else if (computedBase > 0) {
      baseAmount = computedBase;
    } else {
      baseAmount = 0.0;
    }

    if (taxAmount > 0) {
      return baseAmount + taxAmount;
    }

    return baseAmount;
  }

  _InvoiceViewModel _toViewModel(XeroInvoice invoice) {
    final inv = invoice as dynamic;

    final currency = _firstText(
      [
        () => _safe(() => inv.currencyCode),
        () => _mapValue(inv, 'currencyCode'),
        () => _safe(() => inv.currency),
        () => _mapValue(inv, 'currency'),
      ],
      fallback: 'AUD',
    );

    final reference = _firstText([
      () => _safe(() => inv.reference),
      () => _mapValue(inv, 'reference'),
    ]);

    final date = _formatDate(_firstValue([
      () => _safe(() => inv.date),
      () => _mapValue(inv, 'date'),
      () => _safe(() => inv.invoiceDate),
      () => _mapValue(inv, 'invoiceDate'),
    ]));

    final dueDate = _formatDate(_firstValue([
      () => _safe(() => inv.dueDate),
      () => _mapValue(inv, 'dueDate'),
    ]));

    final lineItems = _extractRawLineItems(inv)
        .map((item) => _InvoiceLineItemView(
              reference: _lineItemReference(item),
              amount: _lineItemAmount(item),
            ))
        .where((e) => e.reference != '-' || e.amount > 0)
        .toList();

    final subtotalRaw = _asDouble(_firstValue([
      () => _safe(() => inv.subTotal),
      () => _mapValue(inv, 'subTotal'),
      () => _safe(() => inv.subtotal),
      () => _mapValue(inv, 'subtotal'),
      () => _safe(() => inv.totalExcludingTax),
      () => _mapValue(inv, 'totalExcludingTax'),
    ]));

    final gst = _asDouble(_firstValue([
      () => _safe(() => inv.totalTax),
      () => _mapValue(inv, 'totalTax'),
      () => _safe(() => inv.taxAmount),
      () => _mapValue(inv, 'taxAmount'),
      () => _safe(() => inv.tax),
      () => _mapValue(inv, 'tax'),
      () => _safe(() => inv.gst),
      () => _mapValue(inv, 'gst'),
    ]));

    final total = _asDouble(_firstValue([
      () => _safe(() => inv.total),
      () => _mapValue(inv, 'total'),
    ]));

    final amountDue = _asDouble(_firstValue([
      () => _safe(() => inv.amountDue),
      () => _mapValue(inv, 'amountDue'),
      () => _safe(() => inv.total),
      () => _mapValue(inv, 'total'),
    ]));

    final subtotal = subtotalRaw > 0
        ? subtotalRaw
        : (total > 0 && gst > 0)
            ? (total - gst)
            : total;

    return _InvoiceViewModel(
      currency: currency,
      reference: reference,
      date: date,
      dueDate: dueDate,
      lineItems: lineItems,
      subtotal: subtotal,
      gst: gst,
      amountDue: amountDue,
    );
  }

  Widget _buildBudgetSummary(BuildContext context, XeroInvoice invoice) {
    final cs = Theme.of(context).colorScheme;
    final vm = _toViewModel(invoice);

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
              Expanded(
                child: Text(
                  'Invoice summary',
                  style: Theme.of(context).textTheme.titleMedium?.semiBold,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  vm.currency,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          _MetaRow(
            icon: Icons.tag_outlined,
            label: 'Reference',
            value: vm.reference,
          ),
          const SizedBox(height: 6),

          Row(
            children: [
              Expanded(
                child: _MetaRow(
                  icon: Icons.event,
                  label: 'Date',
                  value: vm.date,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetaRow(
                  icon: Icons.event_available,
                  label: 'Due date',
                  value: vm.dueDate,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: Text(
                  'Line items',
                  style: Theme.of(context).textTheme.titleSmall?.semiBold,
                ),
              ),
              if (vm.lineItems.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${vm.lineItems.length}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: cs.onSecondaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: Text(
                  'Reference',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Amount',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (vm.lineItems.isEmpty)
            Text(
              'No line items',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: vm.lineItems.length,
                separatorBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Container(
                    height: 1,
                    color: cs.outline.withValues(alpha: 0.10),
                  ),
                ),
                itemBuilder: (context, i) {
                  final row = vm.lineItems[i];
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.reference,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${vm.currency} ${_formatMoney(row.amount)}',
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

          _CompactAmountRow(
            description: 'Budget',
            value: '${vm.currency} ${_formatMoney(vm.subtotal)}',
          ),
          const SizedBox(height: 8),

          _CompactAmountRow(
            description: 'GST 10%',
            value: '${vm.currency} ${_formatMoney(vm.gst)}',
          ),

          const SizedBox(height: 10),
          Container(height: 1, color: cs.outline.withValues(alpha: 0.12)),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: Text(
                  'Amount Due',
                  style: Theme.of(context).textTheme.titleMedium?.semiBold,
                ),
              ),
              Text(
                '${vm.currency} ${_formatMoney(vm.amountDue)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
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
    final id = widget.invoiceId.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Success'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        color: cs.surface,
                        border: Border.all(
                          color: cs.outline.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.lg),
                                ),
                                child: Icon(
                                  Icons.check_rounded,
                                  size: 26,
                                  color: cs.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Invoice created',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.semiBold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          if (id.isEmpty)
                            const _InlineErrorCard(
                              title: 'Missing invoice id',
                              subtitle:
                                  'This page requires an invoice id in the URL.',
                            )
                          else
                            FutureBuilder<XeroInvoice?>(
                              future: _invoiceFuture,
                              builder: (context, snap) {
                                if (snap.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Padding(
                                    padding:
                                        EdgeInsets.symmetric(vertical: 24),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }

                                if (snap.hasError) {
                                  return _InlineErrorCard(
                                    title: 'Couldn\'t load invoice',
                                    subtitle: snap.error.toString(),
                                  );
                                }

                                final invoice = snap.data;
                                if (invoice == null) {
                                  return const _InlineErrorCard(
                                    title: 'Invoice not found',
                                    subtitle:
                                        'This invoice could not be loaded.',
                                  );
                                }

                                return _buildBudgetSummary(context, invoice);
                              },
                            ),

                          const SizedBox(height: 16),

                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => context.go(AppRoutes.invoice),
                              icon: Icon(
                                Icons.open_in_new,
                                color: cs.onPrimary,
                              ),
                              label: Text(
                                'Just Confirm👍',
                                style: TextStyle(color: cs.onPrimary),
                              ),
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

class _InvoiceViewModel {
  final String currency;
  final String reference;
  final String date;
  final String dueDate;
  final List<_InvoiceLineItemView> lineItems;
  final double subtotal;
  final double gst;
  final double amountDue;

  const _InvoiceViewModel({
    required this.currency,
    required this.reference,
    required this.date,
    required this.dueDate,
    required this.lineItems,
    required this.subtotal,
    required this.gst,
    required this.amountDue,
  });
}

class _InvoiceLineItemView {
  final String reference;
  final double amount;

  const _InvoiceLineItemView({
    required this.reference,
    required this.amount,
  });
}

class _InlineErrorCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _InlineErrorCard({
    required this.title,
    required this.subtitle,
  });

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
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: cs.onErrorContainer,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onErrorContainer,
                ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });

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
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.semiBold,
              ),
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

  const _CompactAmountRow({
    required this.description,
    required this.value,
  });

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
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.semiBold,
        ),
      ],
    );
  }
}