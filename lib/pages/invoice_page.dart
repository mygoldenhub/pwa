import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pwa/components/invoice_details_sheet.dart';
import 'package:pwa/components/app_header.dart';
import 'package:pwa/components/new_invoice_sheet.dart';
import 'package:pwa/models/xero_invoice.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/services/xero_invoice_service.dart';
import 'package:pwa/theme.dart';
import 'package:url_launcher/url_launcher.dart';

class InvoicePage extends StatefulWidget {
  final Object? draft;
  final Object? webhook;
  const InvoicePage({super.key, this.draft, this.webhook});

  @override
  State<InvoicePage> createState() => _InvoicePageState();
}

class _InvoicePageState extends State<InvoicePage> {
  static const int _pageSize = 10;

  final ScrollController _scrollController = ScrollController();
  final List<XeroInvoice> _invoices = <XeroInvoice>[];
  int _nextOffset = 0;

  GoRouter? _router;
  String? _lastLocation;
  bool _skipNextRouteRefresh = true;

  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  Object? _loadError;

  void _sortInvoicesByUpdatedDateUtc() {
    DateTime key(XeroInvoice i) => i.updatedDateUtc ?? i.date ?? DateTime.fromMillisecondsSinceEpoch(0);
    String tie(XeroInvoice i) => (i.invoiceId ?? i.invoiceNum ?? '').toString();

    _invoices.sort((a, b) {
      final c = key(b).compareTo(key(a));
      if (c != 0) return c;
      return tie(b).compareTo(tie(a));
    });
  }

  String _invoiceDedupeKey(XeroInvoice i) {
    final id = (i.invoiceId ?? '').trim();
    if (id.isNotEmpty) return id;
    final num = (i.invoiceNum ?? '').trim();
    final ref = (i.reference ?? '').trim();
    final d = (i.updatedDateUtc ?? i.date)?.toIso8601String() ?? '';
    return '$num|$ref|$d';
  }

  void _mergeInvoicesUnique(Iterable<XeroInvoice> incoming) {
    final byKey = <String, XeroInvoice>{for (final i in _invoices) _invoiceDedupeKey(i): i};
    for (final i in incoming) {
      byKey[_invoiceDedupeKey(i)] = i;
    }
    _invoices
      ..clear()
      ..addAll(byKey.values);
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    _loadInitial();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final nextRouter = GoRouter.of(context);
    if (!identical(_router, nextRouter)) {
      _router?.routeInformationProvider.removeListener(_handleRouteChanged);
      _router = nextRouter;
      _lastLocation = _router!.routeInformationProvider.value.uri.toString();
      _skipNextRouteRefresh = true;
      _router!.routeInformationProvider.addListener(_handleRouteChanged);
    }
  }

  @override
  void dispose() {
    _router?.routeInformationProvider.removeListener(_handleRouteChanged);
    _scrollController
      ..removeListener(_maybeLoadMore)
      ..dispose();
    super.dispose();
  }

  void _handleRouteChanged() {
    if (!mounted) return;
    final router = _router;
    if (router == null) return;

    final loc = router.routeInformationProvider.value.uri.toString();
    final isInvoice = loc == AppRoutes.invoice || loc.startsWith('${AppRoutes.invoice}?') || loc.startsWith('${AppRoutes.invoice}/');
    final wasInvoice = _lastLocation == AppRoutes.invoice || (_lastLocation ?? '').startsWith('${AppRoutes.invoice}?') || (_lastLocation ?? '').startsWith('${AppRoutes.invoice}/');
    _lastLocation = loc;

    // Avoid double-loading on first mount (initState already calls _loadInitial).
    if (_skipNextRouteRefresh) {
      _skipNextRouteRefresh = false;
      return;
    }

    // Whenever we navigate back to the Invoice page, refresh the list so users
    // always see the latest Supabase updates.
    if (isInvoice && !wasInvoice) {
      _refresh();
    }
  }

  void _maybeLoadMore() {
    if (!_hasMore || _isLoadingMore || _isLoadingInitial) return;
    final pos = _scrollController.position;
    if (!pos.hasPixels || !pos.hasContentDimensions) return;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoadingInitial = true;
      _loadError = null;
      _hasMore = true;
      _invoices.clear();
      _nextOffset = 0;
    });

    try {
      final page = await XeroInvoiceService.listMyInvoicesPage(pageSize: _pageSize, offset: 0);
      if (!mounted) return;
      setState(() {
        _nextOffset = page.length;
        _mergeInvoicesUnique(page);
        _sortInvoicesByUpdatedDateUtc();
        _hasMore = page.length == _pageSize;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    } finally {
      if (!mounted) return;
      setState(() => _isLoadingInitial = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoadingMore || _isLoadingInitial) return;
    setState(() {
      _isLoadingMore = true;
      _loadError = null;
    });

    try {
      final page = await XeroInvoiceService.listMyInvoicesPage(pageSize: _pageSize, offset: _nextOffset);
      if (!mounted) return;
      setState(() {
        _nextOffset += page.length;
        _mergeInvoicesUnique(page);
        _sortInvoicesByUpdatedDateUtc();
        _hasMore = page.length == _pageSize;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    } finally {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _refresh() async {
    await _loadInitial();
  }

  String? _extractInvoiceUrl(Object? webhook) {
    if (webhook == null) return null;

    if (webhook is String) {
      final s = webhook.trim();
      if (s.startsWith('http://') || s.startsWith('https://')) return s;
      return null;
    }

    if (webhook is Map) {
      const candidates = <String>[
        'invoice_url',
        'invoiceUrl',
        'xero_invoice_url',
        'xeroInvoiceUrl',
        'url',
        'Url',
        'link',
        'invoice_link',
      ];
      for (final k in candidates) {
        final v = webhook[k];
        if (v is String) {
          final s = v.trim();
          if (s.startsWith('http://') || s.startsWith('https://')) return s;
        }
      }
    }

    return null;
  }

  Future<void> _gotoInvoice(BuildContext context, Object? webhook) async {
    final url = _extractInvoiceUrl(webhook);
    if (url == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('No invoice link returned by workflow.')),
        );
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Invalid invoice URL returned by workflow.')),
        );
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not open invoice link.')),
        );
    }
  }

  Widget _buildDraftCard(BuildContext context, InvoiceDraft draft) {
    final cs = Theme.of(context).colorScheme;
    final total = (draft.totalBudgetCents / 100).toStringAsFixed(2);
    String fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    return Container(
      padding: AppSpacing.paddingXl,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        color: cs.surface,
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, size: 40, color: cs.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text('Invoice draft', style: Theme.of(context).textTheme.titleLarge?.semiBold)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _KvRow(k: 'Total budget', v: '\$$total'),
          _KvRow(k: 'Reference', v: draft.reference),
          _KvRow(k: 'Currency', v: '${draft.currencyCode} @ ${draft.currencyRate}'),
          _KvRow(k: 'Line amount type', v: draft.lineAmountType.label),
          _KvRow(k: 'Date', v: fmt(draft.date)),
          _KvRow(k: 'Due date', v: fmt(draft.dueDate)),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Next step: wire this to Xero invoice creation and line items.',
            style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(BuildContext context, String? status) {
    final cs = Theme.of(context).colorScheme;
    final s = (status ?? '').trim().toUpperCase();
    final isPaid = s == 'PAID';

    // Per product requirement, we only show Paid/Unpaid in the table.
    final display = s.isEmpty ? '-' : (isPaid ? 'Paid' : 'Unpaid');

    final bg = isPaid
        ? AppSemanticColors.success.withValues(alpha: 0.14)
        : cs.primary.withValues(alpha: 0.10);

    final fg = isPaid ? AppSemanticColors.success : cs.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      child: Text(
        display,
        style: Theme.of(context).textTheme.labelSmall?.semiBold.withColor(fg),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  String _fmtBudget(XeroInvoice inv) {
    final currency = (inv.currencyCode ?? '').trim();
    // Treat “budget” as the amount still due; fall back to totals if needed.
    final amount = inv.amountDue ?? inv.total ?? inv.subTotal;
    if (amount == null) return '-';
    final v = amount.toStringAsFixed(2);
    return currency.isEmpty ? v : '$v $currency';
  }

  Widget _buildInvoiceList(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_isLoadingInitial) {
      return Column(
        children: const [
          InvoiceCardSkeleton(),
          SizedBox(height: AppSpacing.md),
          InvoiceCardSkeleton(),
          SizedBox(height: AppSpacing.md),
          InvoiceCardSkeleton(),
        ],
      );
    }

    if (_loadError != null && _invoices.isEmpty) {
      return Container(
        padding: AppSpacing.paddingXl,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          color: cs.surface,
          border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Could not load invoices', style: textTheme.titleMedium?.semiBold),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _loadError.toString(),
              style: textTheme.bodySmall?.withColor(cs.onSurfaceVariant),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _loadInitial,
              icon: Icon(Icons.refresh, color: cs.primary),
              label: Text('Retry', style: textTheme.titleSmall?.withColor(cs.primary)),
            ),
          ],
        ),
      );
    }

    if (_invoices.isEmpty) {
      return Container(
        padding: AppSpacing.paddingXl,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          color: cs.surface,
          border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Icon(Icons.receipt_long, color: cs.onSurfaceVariant),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text('No invoices found yet.', style: textTheme.bodyMedium?.withColor(cs.onSurfaceVariant))),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final inv in _invoices) ...[
          InvoiceCard(
            invoice: inv,
            budgetText: _fmtBudget(inv),
            statusPill: _buildStatusPill(context, inv.status),
            onTap: () => _openInvoiceDetails(inv),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_isLoadingMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)),
                SizedBox(width: AppSpacing.md),
                Text('Loading more…'),
              ],
            ),
          )
        else if (_loadError != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text('Could not load more invoices. Pull to refresh.', style: textTheme.bodySmall?.withColor(cs.onSurfaceVariant)),
          )
        else if (!_hasMore)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text('You’re all caught up.', style: textTheme.bodySmall?.withColor(cs.onSurfaceVariant)),
          ),
      ],
    );
  }

  Future<void> _openInvoiceDetails(XeroInvoice invoice) async {
    final budgetText = _fmtBudget(invoice);
    final statusPill = _buildStatusPill(context, invoice.status);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => InvoiceDetailsDialog(invoice: invoice, budgetText: budgetText, statusPill: statusPill),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final typedDraft = (widget.draft is InvoiceDraft) ? (widget.draft as InvoiceDraft) : null;
    return Scaffold(
      appBar: const AppImpactHeader(title: 'Invoice'),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            controller: _scrollController,
            padding: AppSpacing.paddingLg,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(
                    children: [
                      if (typedDraft != null) ...[
                        _buildDraftCard(context, typedDraft),
                        const SizedBox(height: AppSpacing.lg),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: () => _gotoInvoice(context, widget.webhook),
                            icon: Icon(Icons.open_in_new, color: cs.onPrimary),
                            label: Text('Goto Invoice', style: Theme.of(context).textTheme.titleSmall?.withColor(cs.onPrimary)),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      _buildInvoiceList(context),
                      const SizedBox(height: AppSpacing.xxl),
                    ],
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

class _KvRow extends StatelessWidget {
  final String k;
  final String v;

  const _KvRow({required this.k, required this.v});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: Text(k, style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant))),
          const SizedBox(width: AppSpacing.md),
          Expanded(flex: 6, child: Text(v, style: Theme.of(context).textTheme.bodyMedium?.semiBold)),
        ],
      ),
    );
  }
}

class InvoiceCard extends StatelessWidget {
  final XeroInvoice invoice;
  final String budgetText;
  final Widget statusPill;
  final VoidCallback? onTap;

  const InvoiceCard({super.key, required this.invoice, required this.budgetText, required this.statusPill, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    String fmtDateTime(DateTime? d) {
      if (d == null) return '-';
      final local = d.toLocal();
      final y = local.year.toString().padLeft(4, '0');
      final m = local.month.toString().padLeft(2, '0');
      final day = local.day.toString().padLeft(2, '0');
      final hh = local.hour.toString().padLeft(2, '0');
      final mm = local.minute.toString().padLeft(2, '0');
      return '$y-$m-$day $hh:$mm';
    }

    final invoiceNum = (invoice.invoiceNum ?? '').trim();
    final reference = (invoice.reference ?? '').trim();
    final title = invoiceNum.isNotEmpty ? invoiceNum : 'Invoice';
    final updatedDateText = fmtDateTime(invoice.updatedDateUtc ?? invoice.date);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStatePropertyAll(cs.primary.withValues(alpha: 0.06)),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Container(
          padding: AppSpacing.paddingLg,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            color: cs.surface,
            border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: cs.primary.withValues(alpha: 0.10),
                      border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
                    ),
                    child: Icon(Icons.receipt_long, color: cs.primary),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: Text(title, style: textTheme.titleMedium?.semiBold, softWrap: true)),
                            const SizedBox(width: AppSpacing.sm),
                            statusPill,
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: Text(updatedDateText, style: textTheme.labelSmall?.withColor(cs.onSurfaceVariant), softWrap: true)),
                            if (onTap != null) ...[
                              const SizedBox(width: AppSpacing.sm),
                              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _CardKvRow(label: 'Reference', value: reference.isEmpty ? '-' : reference),
              const SizedBox(height: AppSpacing.sm),
              _CardKvRow(label: 'Budget', value: budgetText),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardKvRow extends StatelessWidget {
  final String label;
  final String value;

  const _CardKvRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: textTheme.labelSmall?.withColor(cs.onSurfaceVariant))),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          flex: 2,
          child: Text(value, style: textTheme.bodyMedium?.semiBold, softWrap: true, textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

class InvoiceCardSkeleton extends StatelessWidget {
  const InvoiceCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget bar({required double w, required double h}) {
      return Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999),
        ),
      );
    }

    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        color: cs.surface,
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: bar(w: 160, h: 14)),
                        const SizedBox(width: AppSpacing.sm),
                        bar(w: 66, h: 22),
                      ],
                    ),
                    const SizedBox(height: 8),
                    bar(w: 220, h: 10),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          bar(w: double.infinity, h: 10),
          const SizedBox(height: AppSpacing.sm),
          bar(w: double.infinity, h: 10),
        ],
      ),
    );
  }
}

