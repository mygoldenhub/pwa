import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:pwa/app_state.dart';
import 'package:pwa/nav.dart';
import 'package:pwa/services/admin_dashboard_service.dart';
import 'package:pwa/theme.dart';
import 'package:pwa/utils/app_time.dart';

enum AdminSection {
  users,
  pricing,
  products,
  invoices,
  announcements;

  String get query => name;

  String get label => switch (this) {
        AdminSection.users => 'User Management',
        AdminSection.pricing => 'Customer Tiers & Pricing',
        AdminSection.products => 'Product Management',
        AdminSection.invoices => 'Invoice Management',
        AdminSection.announcements => 'Broadcast Announcements',
      };

  IconData get icon => switch (this) {
        AdminSection.users => Icons.group_outlined,
        AdminSection.pricing => Icons.sell_outlined,
        AdminSection.products => Icons.inventory_2_outlined,
        AdminSection.invoices => Icons.receipt_long_outlined,
        AdminSection.announcements => Icons.campaign_outlined,
      };

  static AdminSection fromQuery(String? raw) {
    for (final section in AdminSection.values) {
      if (section.query == raw) return section;
    }
    return AdminSection.users;
  }
}

class AdminDashboardPage extends StatefulWidget {
  final AppState appState;
  const AdminDashboardPage({super.key, required this.appState});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final _searchController = TextEditingController();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  AdminSection _section = AdminSection.users;
  String? _appliedTab;
  String _query = '';
  Timer? _searchDebounce;
  final Map<AdminSection, int> _pageIndex = {};
  final Map<AdminSection, int> _totals = {};
  final Map<AdminSection, String> _loadedQuery = {};
  final Map<AdminSection, int> _loadedPage = {};
  bool _loading = false;
  bool _posting = false;
  String? _error;
  String? _savingUserId;
  String? _savingPricingId;
  String? _savingPricingField;
  String? _formattingUserId;
  String? _removingUserId;
  String? _savingStatusUserId;
  AdminSection? _loadingSection;
  final Map<AdminSection, Object> _tokens = {};

  List<AdminUserRecord> _users = [];
  List<AdminCustomerPricingRecord> _pricing = [];
  List<AdminProductRecord> _products = [];
  /// Sort column (display index) and direction per table; defaults match the original fixed order.
  final Map<AdminSection, ({int column, bool ascending})> _sorts = {
    // -1 = no column selected: newest sign-ups first, so new accounts awaiting approval are on top.
    AdminSection.users: (column: -1, ascending: false),
    AdminSection.pricing: (column: 0, ascending: true),
    AdminSection.products: (column: 1, ascending: true),
    AdminSection.invoices: (column: 5, ascending: false),
  };
  List<AdminInvoiceRecord> _invoices = [];
  List<AdminAnnouncementRecord> _announcements = [];
  List<AdminUserRecord> _broadcastPeople = [];
  // Announcements are all loaded at once and paged on the client.
  static const int _announcementPageSize = 10;
  int _announcementPage = 0;
  final Set<AdminSection> _loaded = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final raw = GoRouterState.of(context).uri.queryParameters['tab'] ?? AdminSection.users.query;
    if (_appliedTab == raw) return;
    _appliedTab = raw;
    final next = AdminSection.fromQuery(raw);
    if (_section != next) {
      setState(() => _section = next);
    }
    _ensureLoaded(next);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _select(AdminSection section) {
    if (section == _section) return;
    _appliedTab = section.query;
    setState(() {
      _section = section;
      _query = '';
      _searchController.clear();
      _error = null;
      _loading = _loadingSection == section;
    });
    _searchDebounce?.cancel();
    final params = section == AdminSection.users ? null : {'tab': section.query};
    GoRouter.of(context).replace(Uri(path: AppRoutes.admin, queryParameters: params).toString());
    _ensureLoaded(section);
  }

  Future<void> _ensureLoaded(AdminSection section, {bool force = false}) async {
    final page = _pageIndex[section] ?? 0;
    final query = section == AdminSection.announcements ? '' : (section == _section ? _query : (_loadedQuery[section] ?? ''));
    if (!force && _loaded.contains(section) && _loadedQuery[section] == query && _loadedPage[section] == page) return;
    final token = Object();
    _tokens[section] = token;
    if (mounted) {
      setState(() {
        _loadingSection = section;
        if (_section == section) {
          _loading = true;
          _error = null;
        }
      });
    }

    final sort = _sorts[section] ?? (column: 0, ascending: true);
    try {
      switch (section) {
        case AdminSection.users:
          final result = await AdminDashboardService.listUsers(
            page: page,
            query: query,
            sortColumn: sort.column,
            ascending: sort.ascending,
          );
          if (!_isCurrent(section, token)) return;
          if (await _retreatIfPageIsEmpty(section, token, page, result.total)) return;
          setState(() => _users = result.rows);
          _rememberPage(section, query, page, result.total);
        case AdminSection.pricing:
          final result = await AdminDashboardService.listCustomerPricing(
            page: page,
            query: query,
            sortColumn: sort.column < 0 ? 0 : sort.column,
            ascending: sort.ascending,
          );
          if (!_isCurrent(section, token)) return;
          if (await _retreatIfPageIsEmpty(section, token, page, result.total)) return;
          setState(() => _pricing = result.rows);
          _rememberPage(section, query, page, result.total);
        case AdminSection.products:
          final result = await AdminDashboardService.listProducts(
            page: page,
            query: query,
            sortColumn: sort.column,
            ascending: sort.ascending,
          );
          if (!_isCurrent(section, token)) return;
          if (await _retreatIfPageIsEmpty(section, token, page, result.total)) return;
          setState(() => _products = result.rows);
          _rememberPage(section, query, page, result.total);
        case AdminSection.invoices:
          final result = await AdminDashboardService.listInvoices(
            page: page,
            query: query,
            sortColumn: sort.column,
            ascending: sort.ascending,
          );
          if (!_isCurrent(section, token)) return;
          if (await _retreatIfPageIsEmpty(section, token, page, result.total)) return;
          setState(() => _invoices = result.rows);
          _rememberPage(section, query, page, result.total);
        case AdminSection.announcements:
          final rows = await AdminDashboardService.listAnnouncements();
          List<AdminUserRecord> people = _broadcastPeople;
          try {
            people = await AdminDashboardService.listBroadcastRecipients();
          } catch (e) {
            debugPrint('Admin dashboard: could not load broadcast recipients: $e');
          }
          if (!_isCurrent(section, token)) return;
          setState(() {
            _announcements = rows;
            _broadcastPeople = people;
          });
          _rememberPage(section, '', 0, rows.length);
      }
      _loaded.add(section);
    } catch (e) {
      if (!_isCurrent(section, token)) return;
      setState(() => _error = _message(e));
    } finally {
      if (_isCurrent(section, token)) {
        setState(() {
          if (_loadingSection == section) _loadingSection = null;
          if (_section == section) _loading = false;
        });
      }
    }
  }

  bool _isCurrent(AdminSection section, Object token) => mounted && _tokens[section] == token;

  void _rememberPage(AdminSection section, String query, int page, int total) {
    _loadedQuery[section] = query;
    _loadedPage[section] = page;
    _totals[section] = total;
    _pageIndex[section] = page;
  }

  /// Loads the last page when the requested page is past the end of a shorter result.
  Future<bool> _retreatIfPageIsEmpty(AdminSection section, Object token, int page, int total) async {
    if (total <= 0 || page == 0) return false;
    final last = (total - 1) ~/ AdminDashboardService.pageSize;
    if (page <= last) return false;
    if (!_isCurrent(section, token)) return true;
    _pageIndex[section] = last;
    _loaded.remove(section);
    await _ensureLoaded(section, force: true);
    return true;
  }

  void _goToPage(int page) {
    final current = _pageIndex[_section] ?? 0;
    if (page == current || page < 0) return;
    setState(() => _pageIndex[_section] = page);
    _ensureLoaded(_section, force: true);
  }

  void _sortBy(int columnIndex) {
    final section = _section;
    final current = _sorts[section];
    setState(() {
      _sorts[section] = current != null && current.column == columnIndex
          ? (column: columnIndex, ascending: !current.ascending)
          : (column: columnIndex, ascending: true);
      _pageIndex[section] = 0;
    });
    _ensureLoaded(section, force: true);
  }

  Widget _creditPlanControl(AdminCustomerPricingRecord row) {
    final saving = _savingPricingId == row.id;
    final selected = switch (row.creditPlan) {
      5000 => 5000,
      3000 => 3000,
      _ => 1000,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: selected,
            isDense: true,
            items: const [
              DropdownMenuItem(value: 5000, child: Text('Gold (5000\$)')),
              DropdownMenuItem(value: 3000, child: Text('Silver (3000\$)')),
              DropdownMenuItem(value: 1000, child: Text('Bronze (1000\$)')),
            ],
            onChanged: saving
                ? null
                : (value) {
                    if (value == null || value == selected) return;
                    _savePricing(row, creditPlan: value.toString());
                  },
          ),
        ),
        if (saving && _savingPricingField == 'plan') ...[
          const SizedBox(width: 8),
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ],
    );
  }

  static const _invoiceTermChoices = ['7 days', '14 days', '30 days'];

  String _pricingNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  String _invoiceTermsValue(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == '14' || value == '14 days') return '14 days';
    if (value == '30' || value == '30 days') return '30 days';
    return '7 days';
  }

  Widget _invoiceTermsControl(AdminCustomerPricingRecord row) {
    final saving = _savingPricingId == row.id;
    final selected = _invoiceTermsValue(row.invoiceTerms);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selected,
            isDense: true,
            items: const [
              DropdownMenuItem(value: '7 days', child: Text('7 days')),
              DropdownMenuItem(value: '14 days', child: Text('14 days')),
              DropdownMenuItem(value: '30 days', child: Text('30 days')),
            ],
            onChanged: saving
                ? null
                : (value) {
                    if (value == null || value == selected) return;
                    _savePricing(row, invoiceTerms: value);
                  },
          ),
        ),
        if (saving && _savingPricingField == 'terms') ...[
          const SizedBox(width: 8),
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ],
    );
  }

  String _creditPlanLabel(double plan) {
    return switch (plan) {
      5000 => 'Gold (5000\$)',
      3000 => 'Silver (3000\$)',
      _ => 'Bronze (1000\$)',
    };
  }

  Future<bool> _savePricing(
    AdminCustomerPricingRecord row, {
    String? creditPlan,
    String? invoiceTerms,
  }) async {
    late final AdminCustomerPricingRecord next;
    if (creditPlan != null) {
      final parsed = double.tryParse(creditPlan.trim());
      if (parsed == null || (parsed != 1000 && parsed != 3000 && parsed != 5000)) {
        _pricingError('Choose Gold, Silver, or Bronze.');
        return false;
      }
      if (parsed == row.creditPlan) return false;
      next = row.copyWith(creditPlan: parsed);
    } else if (invoiceTerms != null) {
      if (!_invoiceTermChoices.contains(invoiceTerms)) {
        _pricingError('Choose 7 days, 14 days, or 30 days.');
        return false;
      }
      if (invoiceTerms == row.invoiceTerms) return false;
      next = row.copyWith(invoiceTerms: invoiceTerms);
    } else {
      return true;
    }

    final field = creditPlan != null ? 'plan' : 'terms';
    setState(() {
      _savingPricingId = row.id;
      _savingPricingField = field;
    });
    try {
      await AdminDashboardService.saveCustomerPricing(next);
      if (!mounted) return true;
      final who = row.displayName == '—' ? row.email : row.displayName;
      final notice = field == 'plan'
          ? "$who's credit plan is now ${_creditPlanLabel(next.creditPlan)}."
          : "$who's invoice terms are now ${next.invoiceTerms}.";
      setState(() {
        _pricing = [for (final item in _pricing) if (item.id == row.id) next else item];
        if (_savingPricingId == row.id) {
          _savingPricingId = null;
          _savingPricingField = null;
        }
      });
      _pricingNotice(notice);
      return true;
    } catch (e) {
      if (mounted) _pricingError(_message(e));
      return false;
    } finally {
      if (mounted && _savingPricingId == row.id) {
        setState(() {
          _savingPricingId = null;
          _savingPricingField = null;
        });
      }
    }
  }

  void _pricingNotice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        content: Text(message),
      ));
  }

  void _pricingError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openProduct(AdminProductRecord product) {
    if (product.id.isEmpty || product.id == '—') return;
    showDialog<void>(
      context: context,
      builder: (context) => _ProductDetailDialog(product: product),
    );
  }

  void _openInvoice(AdminInvoiceRecord invoice) {
    if (invoice.id.isEmpty || invoice.id == '—') return;
    showDialog<void>(
      context: context,
      builder: (context) => _InvoiceDetailDialog(invoice: invoice),
    );
  }

  Future<void> _formatPassword(AdminUserRecord user) async {
    if (_formattingUserId != null) return;
    const password = AdminDashboardService.defaultPassword;
    final who = user.displayName == '—' ? user.email : user.displayName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Format password?'),
        content: Text(
          "$who's password will be changed to $password. "
          'Their current password will stop working immediately.',
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Format password')),
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _formattingUserId = user.id);
    try {
      await AdminDashboardService.formatUserPassword(user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          content: Text("$who's password is formatted with $password"),
        ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(e))));
    } finally {
      if (mounted) setState(() => _formattingUserId = null);
    }
  }

  Future<void> _removeAccount(AdminUserRecord user) async {
    if (_removingUserId != null) return;
    final who = user.displayName == '—' ? user.email : user.displayName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove account?'),
        content: Text("$who's login and profile will be deleted. This cannot be undone."),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove account'),
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _removingUserId = user.id);
    try {
      await AdminDashboardService.removeUserAccount(user);
      if (!mounted) return;
      setState(() => _users = [for (final row in _users) if (row.id != user.id) row]);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text("$who's account was removed."),
        ));
      // Reload so paging and totals stay correct.
      unawaited(_ensureLoaded(AdminSection.users, force: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(e))));
    } finally {
      if (mounted) setState(() => _removingUserId = null);
    }
  }

  Future<void> _changeStatus(AdminUserRecord user, int status) async {
    if (user.status == status || _savingStatusUserId != null) return;
    final who = user.displayName == '—' ? user.email : user.displayName;
    setState(() => _savingStatusUserId = user.id);
    try {
      await AdminDashboardService.setUserStatus(userId: user.id, status: status);
      if (!mounted) return;
      setState(() {
        _users = [
          for (final row in _users) row.id == user.id ? row.copyWith(status: status) : row,
        ];
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(status == 1 ? '$who can now log in.' : '$who can no longer log in.'),
        ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(e))));
    } finally {
      if (mounted) setState(() => _savingStatusUserId = null);
    }
  }

  Future<void> _changeRole(AdminUserRecord user, int role) async {
    if (user.role == role || _savingUserId != null) return;
    setState(() => _savingUserId = user.id);
    try {
      await AdminDashboardService.setUserRole(userId: user.id, role: role);
      if (!mounted) return;
      setState(() {
        _users = [
          for (final row in _users) row.id == user.id ? row.copyWith(role: role) : row,
        ];
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(e))));
    } finally {
      if (mounted) setState(() => _savingUserId = null);
    }
  }

  Future<bool> _publishAnnouncement(List<String> recipientIds) async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a title and a message.')),
      );
      return false;
    }
    final createdBy = widget.appState.auth.currentUser?.id ?? '';
    if (createdBy.isEmpty) return false;
    setState(() => _posting = true);
    try {
      final created = await AdminDashboardService.createAnnouncement(
        title: title,
        body: body,
        createdBy: createdBy,
        recipientIds: recipientIds,
      );
      if (!mounted) return false;
      setState(() {
        _announcements = [created, ..._announcements];
        _announcementPage = 0; // show the new one at the top of page 1
        _titleController.clear();
        _bodyController.clear();
      });
      final audience = _audienceLabel(created);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Announcement published to $audience.')));
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(e))));
      return false;
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  String _audienceLabel(AdminAnnouncementRecord item) {
    if (item.sendsToEveryone) return 'Everyone';
    final names = <String>[
      for (final id in item.recipientIds) _personName(id),
    ];
    if (names.length <= 3) return names.join(', ');
    return '${names.take(2).join(', ')} +${names.length - 2}';
  }

  String _personName(String id) {
    for (final person in _broadcastPeople) {
      if (person.id == id) {
        final name = person.displayName.trim();
        return name.isEmpty || name == '—' ? person.email : name;
      }
    }
    return 'User';
  }

  Future<void> _deleteAnnouncement(AdminAnnouncementRecord item) async {
    final title = item.title.trim().isEmpty ? 'this announcement' : '"${item.title.trim()}"';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete announcement?'),
        content: Text('$title will be removed for all users. This cannot be undone.'),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await AdminDashboardService.deleteAnnouncement(item.id);
      if (!mounted) return;
      setState(() => _announcements = _announcements.where((row) => row.id != item.id).toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(e))));
    }
  }

  Future<void> _signOut() async {
    await widget.appState.auth.signOut();
    if (mounted) context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.appState.auth.currentUser;
    final cs = Theme.of(context).colorScheme;

    final content = Column(
      children: [
        _AdminHeader(
          name: user?.displayName ?? 'Admin',
          email: user?.email ?? '',
          section: _section,
          onSelect: _select,
          onOpenApp: () => context.go(AppRoutes.cart),
          onLogout: _signOut,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: _section == AdminSection.announcements ? _announcementsBody() : _tableBody(),
              ),
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // On short windows the header + toolbar + pager leave no room for the table;
          // give the page a minimum height and let it scroll vertically instead of overflowing.
          const minHeight = 560.0;
          if (!constraints.hasBoundedHeight || constraints.maxHeight >= minHeight) return content;
          return SingleChildScrollView(
            child: SizedBox(height: minHeight, child: content),
          );
        },
      ),
    );
  }

  Widget _tableBody() {
    final rows = _filteredRows();
    final total = _totals[_section] ?? rows.length;
    final page = _pageIndex[_section] ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(count: total, showLoadingText: false),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(message: _error!),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: rows.isEmpty
                    ? (_loading ? const SizedBox.shrink() : const _EmptyState(message: 'Nothing matches this view.'))
                    : _AdminDataTable(
                        columns: _columnLabels(),
                        rows: rows,
                        sortColumn: _sorts[_section]?.column,
                        sortAscending: _sorts[_section]?.ascending ?? true,
                        onSort: _loading ? null : _sortBy,
                        unsortableColumns: _section == AdminSection.users ? const {6, 7} : const {},
                        onRowTap: switch (_section) {
                          AdminSection.products => (index) => _openProduct(_products[index]),
                          AdminSection.invoices => (index) => _openInvoice(_invoices[index]),
                          _ => null,
                        },
                      ),
              ),
              if (_loading)
                Positioned.fill(
                  // Dims the stale page and blocks clicks until the new page arrives.
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
                    child: const Center(child: _LoadingSpinner()),
                  ),
                ),
            ],
          ),
        ),
        if (total > 0)
          _TablePager(
            page: page,
            total: total,
            pageSize: AdminDashboardService.pageSize,
            onPage: _goToPage,
          ),
      ],
    );
  }

  Widget _announcementsBody() {
    final items = _filteredAnnouncements();
    final total = items.length;
    final pageCount = total == 0 ? 1 : (total + _announcementPageSize - 1) ~/ _announcementPageSize;
    // Clamp so deleting the last item on the last page falls back to the previous page.
    final page = _announcementPage.clamp(0, pageCount - 1);
    final pageItems = items.skip(page * _announcementPageSize).take(_announcementPageSize).toList();
    final pager = total > _announcementPageSize
        ? _TablePager(
            page: page,
            total: total,
            pageSize: _announcementPageSize,
            onPage: (p) => setState(() => _announcementPage = p.clamp(0, pageCount - 1)),
          )
        : null;
    final historyList = ListView.separated(
      key: ValueKey('announcement-page-$page'),
      itemCount: pageItems.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = pageItems[index];
        return _AnnouncementCard(
          item: item,
          audience: _audienceLabel(item),
          onDelete: () => _deleteAnnouncement(item),
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(count: items.length, searchHint: 'Search announcements', showLoadingText: false),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(message: _error!),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final composer = _AnnouncementComposer(
                titleController: _titleController,
                bodyController: _bodyController,
                posting: _posting,
                people: _broadcastPeople,
                onPublish: _publishAnnouncement,
              );
              final history = _AnnouncementListPane(
                loading: _loading,
                itemsEmpty: items.isEmpty,
                pager: pager,
                list: historyList,
              );
              if (constraints.maxWidth < 980) {
                return ListView(
                  children: [
                    composer,
                    const SizedBox(height: 16),
                    SizedBox(height: 360, child: history),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Scrolls when the window is too short for the full composer form.
                  SizedBox(width: 380, child: SingleChildScrollView(child: composer)),
                  const SizedBox(width: 20),
                  Expanded(child: history),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _toolbar({required int count, String searchHint = 'Search', bool showLoadingText = true}) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_section.label, style: theme.textTheme.headlineSmall?.semiBold),
            const SizedBox(height: 2),
            Text(
              _loading && showLoadingText ? 'Loading…' : '$count records',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Flexible lets the 280px search field shrink on phone widths.
            Flexible(
              child: SizedBox(
                width: 280,
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _query = value.trim().toLowerCase();
                      if (_section != AdminSection.announcements) {
                        _pageIndex[_section] = 0;
                      } else {
                        _announcementPage = 0;
                      }
                    });
                    if (_section == AdminSection.announcements) return;
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                      if (mounted) _ensureLoaded(_section, force: true);
                    });
                  },
                  decoration: InputDecoration(
                    hintText: searchHint,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : () => _ensureLoaded(_section, force: true),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ],
    );
  }

  List<String> _columnLabels() {
    return switch (_section) {
      AdminSection.users => const ['Name', 'Email', 'Company', 'Phone', 'Role', 'Status', 'Password', 'Account'],
      AdminSection.pricing => const ['Name', 'Email', 'Company', 'Credit plan', 'Credit used', 'Invoice terms'],
      AdminSection.products => const ['Code', 'Name', 'On hand', 'Price', 'Updated'],
      AdminSection.invoices => const ['Number', 'Customer', 'Status', 'Total', 'Due', 'Issued'],
      AdminSection.announcements => const [],
    };
  }

  List<List<Widget>> _filteredRows() {
    switch (_section) {
      case AdminSection.users:
        final currentId = widget.appState.auth.currentUser?.id;
        return [
          for (final user in _users)
            [
              Text(user.displayName),
              Text(user.email),
              Text(user.companyName),
              Text(user.phoneNumber),
              _roleControl(user, isSelf: user.id == currentId),
              _statusControl(user, isSelf: user.id == currentId),
              _formatPasswordButton(user, isSelf: user.id == currentId),
              _removeAccountButton(user, isSelf: user.id == currentId),
            ],
        ];
      case AdminSection.pricing:
        return [
          for (final row in _pricing)
            [
              Text(row.displayName),
              Text(row.email),
              Text(row.companyName),
              _creditPlanControl(row),
              Text(_pricingNumber(row.creditUsed)),
              _invoiceTermsControl(row),
            ],
        ];
      case AdminSection.products:
        return [
          for (final product in _products)
            [
              Text(product.code),
              Text(product.name),
              Text(product.stock),
              Text(product.price),
              Text(_formatDate(product.updatedAt)),
            ],
        ];
      case AdminSection.invoices:
        return [
          for (final invoice in _invoices)
            [
              Text(invoice.number),
              Text(invoice.customer),
              _StatusChip(status: invoice.status),
              Text(invoice.total),
              Text(invoice.amountDue),
              Text(_formatDate(invoice.issuedAt)),
            ],
        ];
      case AdminSection.announcements:
        return const [];
    }
  }

  List<AdminAnnouncementRecord> _filteredAnnouncements() {
    final query = _query;
    if (query.isEmpty) return _announcements;
    return _announcements.where((item) {
      final audience = _audienceLabel(item).toLowerCase();
      return item.title.toLowerCase().contains(query) || item.body.toLowerCase().contains(query) || audience.contains(query);
    }).toList();
  }

  Widget _formatPasswordButton(AdminUserRecord user, {required bool isSelf}) {
    final busy = _formattingUserId == user.id;
    final button = OutlinedButton.icon(
      onPressed: isSelf || _formattingUserId != null ? null : () => _formatPassword(user),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      icon: busy
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
          : const Icon(Icons.lock_reset, size: 16),
      label: const Text('Format password'),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: isSelf ? Tooltip(message: 'Change your own password from Account settings.', child: button) : button,
    );
  }

  Widget _removeAccountButton(AdminUserRecord user, {required bool isSelf}) {
    final busy = _removingUserId == user.id;
    final error = Theme.of(context).colorScheme.error;
    final button = OutlinedButton.icon(
      onPressed: isSelf || _removingUserId != null ? null : () => _removeAccount(user),
      style: OutlinedButton.styleFrom(
        foregroundColor: error,
        side: BorderSide(color: isSelf ? Theme.of(context).disabledColor : error),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      icon: busy
          ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: error))
          : const Icon(Icons.person_remove_outlined, size: 16),
      label: const Text('Remove'),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: isSelf ? Tooltip(message: "You can't remove your own account.", child: button) : button,
    );
  }

  Widget _statusControl(AdminUserRecord user, {required bool isSelf}) {
    final saving = _savingStatusUserId == user.id;
    final cs = Theme.of(context).colorScheme;
    const allowedColor = Color(0xFF1B7F3B);
    final color = user.status == 1 ? allowedColor : cs.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(user.status == 1 ? Icons.check_circle : Icons.block, size: 16, color: color),
        const SizedBox(width: 6),
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: user.status == 1 ? 1 : 0,
            isDense: true,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
            items: [
              const DropdownMenuItem(value: 1, child: Text('Allowed', style: TextStyle(color: allowedColor))),
              DropdownMenuItem(value: 0, child: Text('Not allowed', style: TextStyle(color: cs.error))),
            ],
            // Admins can't block themselves out of the dashboard.
            onChanged: isSelf || saving || _savingStatusUserId != null
                ? null
                : (value) {
                    if (value != null) _changeStatus(user, value);
                  },
          ),
        ),
        if (saving) ...[
          const SizedBox(width: 8),
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)),
        ],
      ],
    );
  }

  Widget _roleControl(AdminUserRecord user, {required bool isSelf}) {
    final saving = _savingUserId == user.id;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: user.role == 0 || user.role == 1 ? user.role : null,
            hint: Text(_roleLabel(user.role)),
            isDense: true,
            items: const [
              DropdownMenuItem(value: 0, child: Text('User')),
              DropdownMenuItem(value: 1, child: Text('Admin')),
            ],
            onChanged: isSelf || saving ? null : (value) {
              if (value != null) _changeRole(user, value);
            },
          ),
        ),
        if (isSelf) ...[
          const SizedBox(width: 8),
          const _StatusChip(status: 'You'),
        ],
        if (saving) ...[
          const SizedBox(width: 8),
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ],
    );
  }
}

class _AdminHeader extends StatelessWidget {
  final String name;
  final String email;
  final AdminSection section;
  final ValueChanged<AdminSection> onSelect;
  final VoidCallback onOpenApp;
  final VoidCallback onLogout;

  const _AdminHeader({
    required this.name,
    required this.email,
    required this.section,
    required this.onSelect,
    required this.onOpenApp,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 520;
    return Material(
      color: cs.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outline.withValues(alpha: 0.12)))),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/images/admin_diamond.png',
                      width: 40,
                      height: 40,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Admin Dashboard',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.semiBold,
                          ),
                          Text(
                            email.isEmpty ? name : '$name · $email',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    // Phone widths: icon-only buttons (same actions, labels as tooltips) so the
                    // name/email column keeps room instead of being squeezed to nothing.
                    if (compact) ...[
                      IconButton(
                        tooltip: 'Open app',
                        onPressed: onOpenApp,
                        icon: const Icon(Icons.open_in_new, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Log out',
                        onPressed: onLogout,
                        icon: const Icon(Icons.logout, size: 18),
                      ),
                    ] else ...[
                      TextButton.icon(
                        onPressed: onOpenApp,
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Open app'),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: onLogout,
                        icon: const Icon(Icons.logout, size: 18),
                        label: const Text('Log out'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final tab in AdminSection.values) ...[
                        _HeaderTab(
                          label: tab.label,
                          icon: tab.icon,
                          selected: tab == section,
                          onTap: () => onSelect(tab),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
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

class _HeaderTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _HeaderTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final background = selected ? cs.primary : Colors.transparent;
    final foreground = selected ? cs.onPrimary : cs.onSurface;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? cs.primary : cs.outline.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 8),
              Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: foreground, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminDataTable extends StatefulWidget {
  final List<String> columns;
  final List<List<Widget>> rows;

  /// Index of the sorted column; headers are clickable only when [onSort] is set.
  final int? sortColumn;
  final bool sortAscending;
  final ValueChanged<int>? onSort;

  /// Makes rows clickable when set; receives the row index.
  final ValueChanged<int>? onRowTap;

  /// Column indexes whose headers are never sortable (e.g. action buttons).
  final Set<int> unsortableColumns;

  const _AdminDataTable({
    required this.columns,
    required this.rows,
    this.sortColumn,
    this.sortAscending = true,
    this.onSort,
    this.onRowTap,
    this.unsortableColumns = const {},
  });

  @override
  State<_AdminDataTable> createState() => _AdminDataTableState();
}

class _AdminDataTableState extends State<_AdminDataTable> {
  static const double _minWidth = 1100;
  final _horizontal = ScrollController();
  final _vertical = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  Widget _header(int index, TextStyle? style, ColorScheme cs) {
    final label = Text(widget.columns[index], style: style);
    final onSort = widget.onSort;
    if (onSort == null && widget.sortColumn == null) return label;
    if (widget.unsortableColumns.contains(index)) return label;
    final active = widget.sortColumn == index;
    final icon = active
        ? (widget.sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
        : Icons.unfold_more;
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onSort == null ? null : () => onSort(index),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: label),
              const SizedBox(width: 4),
              Icon(icon, size: 16, color: active ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final headerStyle = theme.textTheme.labelLarge?.semiBold;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Wide tables (users: 8 columns incl. dropdowns/buttons) need more than 1100px so
        // fixed-width cell controls don't overflow their cells; scroll horizontally instead.
        final columnMin = widget.columns.length * 170.0;
        final minWidth = columnMin > _minWidth ? columnMin : _minWidth;
        final width = constraints.maxWidth < minWidth ? minWidth : constraints.maxWidth;
        return Scrollbar(
          controller: _horizontal,
          thumbVisibility: true,
          notificationPredicate: (notification) => notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  ColoredBox(
                    color: cs.surfaceContainerHighest,
                    child: _TableLine(
                      children: [
                        for (var i = 0; i < widget.columns.length; i++) _header(i, headerStyle, cs),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Scrollbar(
                      controller: _vertical,
                      thumbVisibility: true,
                      child: ListView.separated(
                        controller: _vertical,
                        itemCount: widget.rows.length,
                        separatorBuilder: (context, index) => Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
                        itemBuilder: (context, index) {
                          final line = _TableLine(children: widget.rows[index]);
                          final onRowTap = widget.onRowTap;
                          if (onRowTap == null) return line;
                          return InkWell(
                            onTap: () => onRowTap(index),
                            mouseCursor: SystemMouseCursors.click,
                            child: line,
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TableLine extends StatelessWidget {
  final List<Widget> children;
  const _TableLine({required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          for (final child in children)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: child,
              ),
            ),
        ],
      ),
    );
  }
}

/// Broadcast list with the same dimmed spinner the other admin tabs use.
class _AnnouncementListPane extends StatelessWidget {
  final bool loading;
  final bool itemsEmpty;
  final Widget? pager;
  final Widget list;

  const _AnnouncementListPane({
    required this.loading,
    required this.itemsEmpty,
    required this.pager,
    required this.list,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: itemsEmpty
              ? (loading ? const SizedBox.shrink() : const _EmptyState(message: 'No announcements yet.'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: list),
                    if (pager != null) pager!,
                  ],
                ),
        ),
        if (loading)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
              child: const Center(child: _LoadingSpinner()),
            ),
          ),
      ],
    );
  }
}

class _AnnouncementComposer extends StatefulWidget {
  final TextEditingController titleController;
  final TextEditingController bodyController;
  final bool posting;
  final List<AdminUserRecord> people;
  final Future<bool> Function(List<String> recipientIds) onPublish;

  const _AnnouncementComposer({
    required this.titleController,
    required this.bodyController,
    required this.posting,
    required this.people,
    required this.onPublish,
  });

  @override
  State<_AnnouncementComposer> createState() => _AnnouncementComposerState();
}

class _AnnouncementComposerState extends State<_AnnouncementComposer> {
  static const double _menuHeight = 280;

  final Set<String> _selected = {};
  final _sendToLayer = LayerLink();
  final _sendToPortal = OverlayPortalController();
  bool _everyone = false;

  @override
  void didUpdateWidget(covariant _AnnouncementComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = widget.people.map((person) => person.id).toSet();
    if (_everyone) {
      _selected
        ..clear()
        ..addAll(ids);
    } else {
      _selected.removeWhere((id) => !ids.contains(id));
      if (ids.isNotEmpty && _selected.length == ids.length) _everyone = true;
    }
    if (widget.posting && _sendToPortal.isShowing) _sendToPortal.hide();
  }

  void _selectAll() {
    _everyone = true;
    _selected
      ..clear()
      ..addAll(widget.people.map((person) => person.id));
  }

  String _nameOf(AdminUserRecord person) {
    final name = person.displayName.trim();
    return name.isEmpty || name == '—' ? person.email : name;
  }

  String _countLabel(int count) => count == 1 ? '1 user selected' : '$count users selected';

  String get _closedLabel {
    if (_everyone) return 'Everyone';
    if (_selected.isEmpty) return 'Not selected';
    return _countLabel(_selected.length);
  }

  Future<void> _publish() async {
    if (!_everyone && _selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one person, or send to everyone.')),
      );
      return;
    }
    final ids = _everyone ? const <String>[] : _selected.toList();
    final ok = await widget.onPublish(ids);
    if (!ok || !mounted) return;
    setState(() {
      _everyone = false;
      _selected.clear();
      if (_sendToPortal.isShowing) _sendToPortal.hide();
    });
  }

  void _toggleEveryone(bool selected) {
    setState(() {
      if (selected) {
        _selectAll();
      } else {
        _everyone = false;
        _selected.clear();
      }
    });
  }

  void _toggleUser(String id, bool selected) {
    if (_everyone) return;
    setState(() {
      if (selected) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
      if (widget.people.isNotEmpty && _selected.length == widget.people.length) {
        _everyone = true;
      }
    });
  }

  Widget _sendToMenu(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final count = _everyone ? widget.people.length : _selected.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          dense: true,
          value: _everyone,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Everyone'),
          onChanged: widget.posting ? null : (value) => _toggleEveryone(value ?? false),
        ),
        Divider(height: 1, color: cs.outline.withValues(alpha: 0.2)),
        Expanded(
          child: widget.people.isEmpty
              ? Center(
                  child: Text(
                    'No people available yet.',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  itemCount: widget.people.length,
                  itemBuilder: (context, index) {
                    final person = widget.people[index];
                    final checked = _everyone || _selected.contains(person.id);
                    return CheckboxListTile(
                      dense: true,
                      value: checked,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(_nameOf(person), maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(person.email, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onChanged: widget.posting || _everyone
                          ? null
                          : (value) => _toggleUser(person.id, value ?? false),
                    );
                  },
                ),
        ),
        Divider(height: 1, color: cs.outline.withValues(alpha: 0.2)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            _countLabel(count),
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _sendToField(BuildContext context, double width) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return CompositedTransformTarget(
      link: _sendToLayer,
      child: OverlayPortal(
        controller: _sendToPortal,
        overlayChildBuilder: (overlayContext) {
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _sendToPortal.hide,
                ),
              ),
              CompositedTransformFollower(
                link: _sendToLayer,
                targetAnchor: Alignment.bottomLeft,
                followerAnchor: Alignment.topLeft,
                offset: const Offset(0, 4),
                showWhenUnlinked: false,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    height: _menuHeight,
                    child: Material(
                      elevation: 6,
                      color: cs.surface,
                      surfaceTintColor: cs.surfaceTint,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        side: BorderSide(color: cs.outline.withValues(alpha: 0.4)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _sendToMenu(overlayContext),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: InkWell(
          onTap: widget.posting
              ? null
              : () {
                  if (_sendToPortal.isShowing) {
                    _sendToPortal.hide();
                  } else {
                    _sendToPortal.show();
                  }
                },
          borderRadius: BorderRadius.circular(4),
          child: InputDecorator(
            isEmpty: false,
            decoration: InputDecoration(
              labelText: 'Send to',
              border: const OutlineInputBorder(),
              suffixIcon: Icon(_sendToPortal.isShowing ? Icons.arrow_drop_up : Icons.arrow_drop_down),
            ),
            child: Text(
              _closedLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: _everyone || _selected.isNotEmpty ? null : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('New announcement', style: theme.textTheme.titleMedium?.semiBold),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) => _sendToField(context, constraints.maxWidth),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.titleController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.bodyController,
              minLines: 5,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true, border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: widget.posting ? null : _publish,
              icon: widget.posting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.campaign_outlined),
              label: const Text('Publish'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final AdminAnnouncementRecord item;
  final String audience;
  final VoidCallback onDelete;

  const _AnnouncementCard({required this.item, required this.audience, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final radius = BorderRadius.circular(AppRadius.lg);
    final everyone = item.sendsToEveryone;
    final title = item.title.trim().isEmpty ? 'Untitled announcement' : item.title.trim();
    // Tap opens the full announcement in a modal.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: cs.outline.withValues(alpha: 0.10)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            InkWell(
              onTap: () => _showAnnouncementDetail(context, item, audience, onDelete),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 84, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Icon(Icons.campaign_rounded, size: 22, color: cs.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.2),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.body.trim().isEmpty ? 'No message' : item.body.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.35),
                          ),
                          const SizedBox(height: 10),
                          _AudienceChip(label: audience, everyone: everyone),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 14,
              right: 12,
              child: Text(
                _announcementWhen(item.createdAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Positioned(
              right: 2,
              bottom: 2,
              child: IconButton(
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline_rounded, size: 20, color: cs.error.withValues(alpha: 0.85)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudienceChip extends StatelessWidget {
  final String label;
  final bool everyone;

  const _AudienceChip({required this.label, required this.everyone});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = everyone ? cs.primary : cs.onSurfaceVariant;
    final text = label.trim().isEmpty ? (everyone ? 'Everyone' : 'Selected users') : label.trim();
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: everyone ? cs.primary.withValues(alpha: 0.08) : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(everyone ? Icons.public_rounded : Icons.group_outlined, size: 14, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                everyone ? 'Everyone' : text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Just now", "5m ago", "3h ago", "Yesterday", "4d ago", then the local date.
String _announcementWhen(DateTime? createdAt) {
  if (createdAt == null) return '';
  final diff = DateTime.now().toUtc().difference(createdAt.toUtc());
  if (diff.isNegative || diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return AppTime.formatDateDmy(createdAt);
}

/// Full announcement in a modal (opened from an [_AnnouncementCard]).
Future<void> _showAnnouncementDetail(
  BuildContext context,
  AdminAnnouncementRecord item,
  String audience,
  VoidCallback onDelete,
) {
  final theme = Theme.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: Text(item.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppTime.formatDateTime(item.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              'To: $audience',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SelectableText(item.body, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onDelete();
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete'),
        ),
        FilledButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Close')),
      ],
    ),
  );
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(status, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onErrorContainer)),
      ),
    );
  }
}

class _TablePager extends StatelessWidget {
  final int page;
  final int total;
  final int pageSize;
  final ValueChanged<int> onPage;

  const _TablePager({
    required this.page,
    required this.total,
    required this.pageSize,
    required this.onPage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pageCount = total == 0 ? 1 : ((total + pageSize - 1) ~/ pageSize);
    final safePage = page.clamp(0, pageCount - 1);
    final start = total == 0 ? 0 : safePage * pageSize + 1;
    final end = total == 0 ? 0 : (start + pageSize - 1).clamp(start, total);
    final pages = _pageWindow(safePage, pageCount);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Text(
            'Showing $start–$end of $total',
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          // Page buttons can be ~450px wide; scroll them horizontally on phone widths.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PagerButton(
                  label: 'Previous',
                  enabled: safePage > 0,
                  onTap: () => onPage(safePage - 1),
                ),
                const SizedBox(width: 6),
                for (final item in pages) ...[
                  if (item == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text('…'),
                    )
                  else
                    _PagerButton(
                      label: '${item + 1}',
                      selected: item == safePage,
                      onTap: () => onPage(item),
                    ),
                  const SizedBox(width: 4),
                ],
                const SizedBox(width: 2),
                _PagerButton(
                  label: 'Next',
                  enabled: safePage < pageCount - 1,
                  onTap: () => onPage(safePage + 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<int?> _pageWindow(int current, int count) {
    if (count <= 7) return [for (var i = 0; i < count; i++) i];
    final visible = <int>{0, count - 1, current};
    if (current - 1 > 0) visible.add(current - 1);
    if (current + 1 < count - 1) visible.add(current + 1);
    final sorted = visible.toList()..sort();
    final window = <int?>[];
    for (var i = 0; i < sorted.length; i++) {
      if (i > 0 && sorted[i] - sorted[i - 1] > 1) window.add(null);
      window.add(sorted[i]);
    }
    return window;
  }
}

class _PagerButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _PagerButton({
    required this.label,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final background = selected ? cs.primary : Colors.transparent;
    final foreground = !enabled
        ? cs.onSurface.withValues(alpha: 0.35)
        : selected
            ? cs.onPrimary
            : cs.onSurface;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: enabled && !selected ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? cs.primary : cs.outline.withValues(alpha: 0.2)),
          ),
          child: Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: foreground, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

String _roleLabel(int role) {
  return switch (role) {
    0 => 'User',
    1 => 'Admin',
    _ => 'Role $role',
  };
}

/// Black open-arc spinner used while admin table pages load.
class _LoadingSpinner extends StatelessWidget {
  const _LoadingSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 36,
      height: 36,
      child: CircularProgressIndicator(
        strokeWidth: 4,
        strokeCap: StrokeCap.round,
        color: Colors.black,
      ),
    );
  }
}

class _ProductDetailDialog extends StatefulWidget {
  final AdminProductRecord product;
  const _ProductDetailDialog({required this.product});

  @override
  State<_ProductDetailDialog> createState() => _ProductDetailDialogState();
}

class _ProductDetailDialogState extends State<_ProductDetailDialog> {
  late final Future<Map<String, dynamic>> _future = AdminDashboardService.getProduct(widget.product.id);

  @override
  Widget build(BuildContext context) {
    return _DetailDialog(
      title: widget.product.name,
      subtitle: widget.product.code,
      future: _future,
      sections: _sections,
    );
  }

  List<Widget> _sections(Map<String, dynamic> row) {
    final product = widget.product;
    final tracked = row['is_tracked_as_inventory'];
    final overview = <(String, String)>[
      ('Code', product.code),
      ('Name', product.name),
      ('Item ID', _value(row['item_id'] ?? row['xero_item_id'])),
      ('On hand', product.stock),
      ('Sale price', product.price),
      if (tracked != null) ('Tracked as inventory', tracked == true ? 'Yes' : 'No'),
      if (row.containsKey('inventory_asset_account_code'))
        ('Inventory asset account', _value(row['inventory_asset_account_code'])),
      if (row.containsKey('sales_account')) ('Sales account', _value(row['sales_account'])),
      if (row.containsKey('tax_rate')) ('Tax rate', _value(row['tax_rate'])),
      if (row.containsKey('created_at')) ('Created', _formatDateTime(row['created_at'])),
      ('Updated', _formatDateTime(row['updated_date_utc'] ?? row['updated_at'])),
    ];
    final description = _value(row['description']);
    final purchaseDescription = _value(row['purchase_description']);
    return [
      _DetailSection(title: 'Overview', entries: overview),
      if (description != '—') _DetailText(title: 'Description', text: description),
      if (row['sales_details'] is Map)
        _DetailSection(title: 'Sales details', entries: _mapEntries(row['sales_details'] as Map)),
      if (row['purchase_details'] is Map)
        _DetailSection(title: 'Purchase details', entries: _mapEntries(row['purchase_details'] as Map)),
      if (purchaseDescription != '—') _DetailText(title: 'Purchase description', text: purchaseDescription),
    ];
  }
}

class _InvoiceDetailDialog extends StatefulWidget {
  final AdminInvoiceRecord invoice;
  const _InvoiceDetailDialog({required this.invoice});

  @override
  State<_InvoiceDetailDialog> createState() => _InvoiceDetailDialogState();
}

class _InvoiceDetailDialogState extends State<_InvoiceDetailDialog> {
  late final Future<Map<String, dynamic>> _future = AdminDashboardService.getInvoice(widget.invoice.id);

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoice;
    return _DetailDialog(
      title: invoice.number == '—' ? 'Invoice' : invoice.number,
      subtitle: invoice.customer,
      badge: _StatusChip(status: invoice.status),
      maxWidth: 820,
      future: _future,
      sections: _sections,
    );
  }

  List<Widget> _sections(Map<String, dynamic> row) {
    // The legacy xero_invoices table keeps the full Xero payload (PascalCase) in `raw`.
    final raw = row['raw'] is Map ? Map<String, dynamic>.from(row['raw'] as Map) : const <String, dynamic>{};
    dynamic field(String key, [String? rawKey]) => row[key] ?? (rawKey == null ? null : raw[rawKey]);

    final currency = _value(field('currency_code', 'CurrencyCode') ?? row['currency']);
    final cur = currency == '—' ? '' : currency;
    final contact = row['contact'] is Map ? row['contact'] as Map : (raw['Contact'] is Map ? raw['Contact'] as Map : const {});

    // PAID invoices: "Fully paid on" is the invoice's updated_date_utc (UTC) shown in the user's timezone.
    final status = _value(field('status', 'Status'));
    final fullyPaidOn = status.toUpperCase() == 'PAID'
        ? _formatDateTime(field('updated_date_utc', 'UpdatedDateUTC'))
        : _formatDateOnly(field('full_paid_on_date', 'FullyPaidOnDate'));

    final overview = <(String, String)>[
      ('Invoice number', _value(field('invoice_num', 'InvoiceNumber') ?? row['invoice_number'])),
      ('Reference', _value(field('reference', 'Reference'))),
      ('Type', _invoiceType(_value(field('type', 'Type')))),
      ('Status', status),
      ('Customer', _value(contact['name'] ?? contact['Name'])),
      ('Contact ID', _value(contact['contact_id'] ?? contact['ContactID'] ?? row['contact_id'])),
      ('Issued', AppTime.formatDateTime(field('date', 'DateString') ?? row['issue_date'])),
      // due_date_string = created time + 7 days (set by the 0011 trigger); falls back to Xero's due_date.
      ('Due', AppTime.formatDateTime(field('due_date_string', 'DueDateString') ?? row['due_date'])),
      ('Fully paid on', fullyPaidOn),
      ('Currency', currency),
      ('Amounts are', _value(field('line_amount_types', 'LineAmountTypes'))),
      ('Invoice ID', _value(row['invoice_id'] ?? row['xero_invoice_id'])),
      ('Updated', AppTime.formatDateTime(field('updated_date_utc') ?? row['updated_at'])),
    ];

    final amounts = <(String, String)>[
      ('Subtotal', _amount(field('sub_total', 'SubTotal'), cur)),
      ('Tax', _amount(field('total_tax', 'TotalTax'), cur)),
      ('Total', _amount(field('total', 'Total'), cur)),
      ('Paid', _amount(field('amount_paid', 'AmountPaid'), cur)),
      ('Credited', _amount(field('amount_credited', 'AmountCredited'), cur)),
      ('Amount due', _amount(field('amount_due', 'AmountDue'), cur)),
    ];

    final lineItems = _maps(row['line_items'] ?? raw['LineItems']);
    final payments = _maps(row['payments'] ?? raw['Payments']);

    return [
      _DetailSection(title: 'Overview', entries: overview),
      _DetailSection(title: 'Amounts', entries: amounts),
      _LineItemsTable(items: lineItems, currency: cur),
      _PaymentsTable(payments: payments, currency: cur),
    ];
  }

  static String _invoiceType(String type) => switch (type) {
        'ACCREC' => 'Sales invoice (ACCREC)',
        'ACCPAY' => 'Bill (ACCPAY)',
        _ => type,
      };
}

/// Shared frame for admin detail modals: header with close button, then loaded sections.
class _DetailDialog extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? badge;
  final double maxWidth;
  final Future<Map<String, dynamic>> future;
  final List<Widget> Function(Map<String, dynamic> row) sections;

  const _DetailDialog({
    required this.title,
    required this.subtitle,
    required this.future,
    required this.sections,
    this.badge,
    this.maxWidth = 640,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleLarge?.semiBold),
                        const SizedBox(height: 2),
                        Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  if (badge != null) ...[
                    Padding(padding: const EdgeInsets.only(top: 6), child: badge),
                    const SizedBox(width: 8),
                  ],
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
            Flexible(
              child: FutureBuilder<Map<String, dynamic>>(
                future: future,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: _ErrorBanner(message: _message(snapshot.error!)),
                    );
                  }
                  final row = snapshot.data;
                  if (row == null) {
                    return const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: _LoadingSpinner()),
                    );
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: sections(row),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineItemsTable extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final String currency;
  const _LineItemsTable({required this.items, required this.currency});

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final li in items)
        [
          _value(li['item_code'] ?? li['ItemCode'] ?? (li['item'] is Map ? (li['item'] as Map)['code'] : null)),
          _value(li['description'] ?? li['Description']),
          _number(li['quantity'] ?? li['Quantity']),
          _amount(li['unit_amount'] ?? li['UnitAmount'], ''),
          _value(li['tax_type'] ?? li['TaxType']),
          _amount(li['tax_amount'] ?? li['TaxAmount'], ''),
          _amount(li['line_amount'] ?? li['LineAmount'], currency),
        ],
    ];
    return _MiniTable(
      title: 'Line items',
      emptyText: 'No line items recorded.',
      columns: const ['Code', 'Description', 'Qty', 'Unit price', 'Tax type', 'Tax', 'Amount'],
      flex: const [2, 5, 1, 2, 2, 2, 2],
      numeric: const {2, 3, 5, 6},
      rows: rows,
    );
  }
}

class _PaymentsTable extends StatelessWidget {
  final List<Map<String, dynamic>> payments;
  final String currency;
  const _PaymentsTable({required this.payments, required this.currency});

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final p in payments)
        [
          // The sync stores the payment date under `data` (sic).
          _formatDateOnly(p['date'] ?? p['data'] ?? p['Date']),
          _value(p['reference'] ?? p['Reference']),
          _value(p['payment_id'] ?? p['PaymentID']),
          _amount(p['amount'] ?? p['Amount'], currency),
        ],
    ];
    return _MiniTable(
      title: 'Payments',
      emptyText: 'No payments recorded.',
      columns: const ['Date', 'Reference', 'Payment ID', 'Amount'],
      flex: const [2, 3, 4, 2],
      numeric: const {3},
      rows: rows,
    );
  }
}

/// Compact read-only table used inside detail modals.
class _MiniTable extends StatelessWidget {
  final String title;
  final String emptyText;
  final List<String> columns;
  final List<int> flex;
  final Set<int> numeric;
  final List<List<String>> rows;

  const _MiniTable({
    required this.title,
    required this.emptyText,
    required this.columns,
    required this.flex,
    required this.numeric,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant);

    Widget line(List<String> cells, TextStyle? style) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cells.length; i++)
              Expanded(
                flex: flex[i],
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SelectableText(
                    cells[i],
                    style: style,
                    textAlign: numeric.contains(i) ? TextAlign.right : TextAlign.left,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleSmall?.semiBold),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Text(emptyText, style: muted)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final table = DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ColoredBox(
                        color: cs.surfaceContainerHighest,
                        child: line(columns, theme.textTheme.labelLarge?.semiBold),
                      ),
                      for (var r = 0; r < rows.length; r++) ...[
                        if (r > 0) Divider(height: 1, color: cs.outline.withValues(alpha: 0.12)),
                        line(rows[r], theme.textTheme.bodyMedium),
                      ],
                    ],
                  ),
                );
                // On phone widths the columns would be squeezed to a few px each;
                // keep a usable minimum width and scroll horizontally instead.
                final minWidth = columns.length * 90.0;
                if (constraints.maxWidth >= minWidth) return table;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: minWidth, child: table),
                );
              },
            ),
        ],
      ),
    );
  }
}

List<(String, String)> _mapEntries(Map map) {
  return [
    for (final entry in map.entries) (_humanize(entry.key.toString()), _value(entry.value)),
  ];
}

List<Map<String, dynamic>> _maps(dynamic value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

/// Turns `UnitPrice` / `unit_price` into `Unit price`.
String _humanize(String key) {
  final spaced = key
      .replaceAll('_', ' ')
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .trim();
  if (spaced.isEmpty) return key;
  final lower = spaced.toLowerCase();
  return lower[0].toUpperCase() + lower.substring(1);
}

String _value(dynamic value) {
  if (value == null) return '—';
  if (value is Map || value is List) return value.isEmpty ? '—' : value.toString();
  final text = value.toString().trim();
  return text.isEmpty ? '—' : text;
}

double? _toDouble(dynamic value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');

String _amount(dynamic value, String currency) {
  final number = _toDouble(value);
  if (number == null) return '—';
  final text = number.toStringAsFixed(2);
  return currency.isEmpty ? text : '$currency $text';
}

String _number(dynamic value) {
  final number = _toDouble(value);
  if (number == null) return '—';
  return number % 1 == 0 ? number.toInt().toString() : number.toStringAsFixed(2);
}

// All times come from Supabase in UTC and are shown in the user's (device) timezone.
String _formatDateOnly(dynamic value) => AppTime.formatDate(value);

String _formatDateTime(dynamic value) => AppTime.formatDateTime(value);
class _DetailSection extends StatelessWidget {
  final String title;
  final List<(String, String)> entries;
  const _DetailSection({required this.title, required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 200px label column, but never more than 40% of the dialog on phone widths.
        final labelWidth = (constraints.maxWidth * 0.4).clamp(0.0, 200.0);
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: theme.textTheme.titleSmall?.semiBold),
              const SizedBox(height: 8),
              for (final (label, value) in entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: labelWidth,
                        child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                      Expanded(child: SelectableText(value, style: theme.textTheme.bodyMedium)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DetailText extends StatelessWidget {
  final String title;
  final String text;
  const _DetailText({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleSmall?.semiBold),
          const SizedBox(height: 8),
          SelectableText(text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

String _formatDate(DateTime? value) => AppTime.formatDate(value);

String _message(Object error) {
  var text = error is PostgrestException ? error.message : error.toString().replaceFirst('Exception: ', '');
  final lower = text.toLowerCase();
  if (lower.contains('admin_format_user_password') && (lower.contains('could not find') || lower.contains('does not exist'))) {
    return 'Password formatting is not set up yet. Run supabase/migrations/0007_admin_format_password.sql in the Supabase SQL editor.';
  }
  if (lower.contains('status') && lower.contains('column')) {
    return 'User status is not set up yet. Run supabase/migrations/0008_users_status.sql in the Supabase SQL editor.';
  }
  if (lower.contains('credit_used')) {
    return 'Credit used is not set up yet. Run supabase/migrations/0018_users_credit_used.sql in the Supabase SQL editor.';
  }
  if (lower.contains('discount_level')) {
    return 'Discount level has been removed. Run supabase/migrations/0020_drop_discount_level.sql in the Supabase SQL editor.';
  }
  if (lower.contains('credit_plan') || lower.contains('invoice_terms') || lower.contains('customer_pricing')) {
    return 'Customer pricing is not set up yet. Run supabase/migrations/0017_customer_pricing.sql in the Supabase SQL editor.';
  }
  if (lower.contains('row-level security') || lower.contains('permission') || lower.contains('announcements')) {
    text = '$text Run supabase/migrations/0006_admin_access.sql in the Supabase SQL editor.';
  }
  return text;
}
