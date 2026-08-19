import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pwa/components/app_modal.dart';
import 'package:pwa/models/xero_product.dart';
import 'package:pwa/services/xero_product_service.dart';
import 'package:pwa/theme.dart';

Future<XeroProduct?> showXeroProductNamePicker(
  BuildContext context, {
  String initialQuery = '',
}) {
  final cs = Theme.of(context).colorScheme;
  return showDialog<XeroProduct>(
    context: context,
    barrierDismissible: true,
    barrierColor: cs.scrim.withValues(alpha: 0.52),
    builder: (context) => AppCenteredModalDialog(
      child: XeroProductNamePickerSheet(initialQuery: initialQuery),
    ),
  );
}

class XeroProductNamePickerSheet extends StatefulWidget {
  final String initialQuery;

  const XeroProductNamePickerSheet({super.key, required this.initialQuery});

  @override
  State<XeroProductNamePickerSheet> createState() => _XeroProductNamePickerSheetState();
}

class _XeroProductNamePickerSheetState extends State<XeroProductNamePickerSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  String _query = '';
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  int _offset = 0;
  static const int _pageSize = 20;
  List<XeroProduct> _results = const [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialQuery;
    _query = widget.initialQuery;
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _kickoffSearch();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    final q = _query.trim();
    if (q.isEmpty) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _offset = 0;
        _hasMore = false;
        _isLoading = false;
        _isLoadingMore = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _offset = 0;
      _hasMore = false;
    });

    final rows = await XeroProductService.searchByNamePrefixPaged(q, limit: _pageSize, offset: 0);
    if (!mounted) return;
    setState(() {
      _results = rows;
      _offset = rows.length;
      _hasMore = rows.length == _pageSize;
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    final q = _query.trim();
    if (q.isEmpty || _isLoading || _isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final rows = await XeroProductService.searchByNamePrefixPaged(q, limit: _pageSize, offset: _offset);
      if (!mounted) return;
      setState(() {
        final seen = _results.map((e) => e.xeroItemId).toSet();
        final appended = rows.where((r) => r.xeroItemId.isNotEmpty && seen.add(r.xeroItemId)).toList();
        _results = [..._results, ...appended];
        _offset += rows.length;
        _hasMore = rows.length == _pageSize;
      });
    } catch (e) {
      debugPrint('Product name picker loadMore failed: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _kickoffSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () async {
      if (!mounted) return;
      await _loadFirstPage();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenH = MediaQuery.sizeOf(context).height;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final availableH = (screenH - viewInsets.bottom).clamp(0.0, screenH);
    final dialogHeight = (availableH * 0.78).clamp(360.0, screenH * 0.82);

    return SizedBox(
      height: dialogHeight,
      child: AppModalSurface(
        padding: const EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: AppSpacing.lg,
          top: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Product name', style: Theme.of(context).textTheme.titleLarge?.semiBold)),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            Text(
              'Start typing to search products in store.',
              style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: (v) {
                setState(() => _query = v);
                _kickoffSearch();
              },
              decoration: InputDecoration(
                labelText: 'Product name',
                prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
                suffixIcon: _isLoading
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                        ),
                      )
                    : (_query.trim().isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            onPressed: () {
                              _controller.clear();
                              setState(() {
                                _query = '';
                                _results = const [];
                                _offset = 0;
                                _hasMore = false;
                                _isLoadingMore = false;
                              });
                            },
                            icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                          )),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _query.trim().isEmpty
                    ? const _HintPanel(
                        key: ValueKey('hint'),
                        icon: Icons.lightbulb_outline,
                        text: 'Try searching by product name, like “Ardex FG 8 misty grey”.',
                      )
                    : (!_isLoading && _results.isEmpty)
                        ? const _HintPanel(
                            key: ValueKey('empty'),
                            icon: Icons.search_off,
                            text: 'No matches. If you expect products, confirm Xero sync is running and that you have read access to xero_products.',
                          )
                        : ListView.separated(
                            key: const ValueKey('results'),
                            padding: EdgeInsets.zero,
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            controller: _scrollController,
                            primary: false,
                            physics: const BouncingScrollPhysics(),
                            itemCount: _results.length + (_isLoadingMore ? 1 : 0),
                            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                            itemBuilder: (context, index) {
                              if (index >= _results.length) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                                  child: Center(
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                                    ),
                                  ),
                                );
                              }
                              final p = _results[index];
                              return _XeroProductSuggestionTile(
                                product: p,
                                onTap: () => Navigator.of(context).pop(p),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HintPanel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HintPanel({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        color: cs.surface,
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.withColor(cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _XeroProductSuggestionTile extends StatefulWidget {
  final XeroProduct product;
  final VoidCallback onTap;

  const _XeroProductSuggestionTile({required this.product, required this.onTap});

  @override
  State<_XeroProductSuggestionTile> createState() => _XeroProductSuggestionTileState();
}

class _XeroProductSuggestionTileState extends State<_XeroProductSuggestionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = widget.product;
    final subtitle = <String>[
      if ((p.code ?? '').trim().isNotEmpty) 'Code: ${p.code}',
      if (p.salePriceCents != null) '\$${(p.salePriceCents! / 100).toStringAsFixed(2)}',
    ].join(' · ');

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: AppSpacing.paddingLg,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            color: _hovered ? cs.primaryContainer.withValues(alpha: 0.50) : cs.surface,
            border: Border.all(color: _hovered ? cs.primary.withValues(alpha: 0.30) : cs.outline.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  color: cs.secondaryContainer,
                ),
                child: Icon(Icons.inventory_2_outlined, color: cs.onSecondaryContainer),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: Theme.of(context).textTheme.titleMedium?.semiBold),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.withColor(cs.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
