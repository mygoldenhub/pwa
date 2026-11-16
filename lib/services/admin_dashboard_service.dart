import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pwa/supabase/supabase_config.dart';
import 'package:pwa/utils/app_time.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminUserRecord {
  final String id;
  final String email;
  final String displayName;
  final String companyName;
  final String phoneNumber;
  final int role;

  /// `1` may log in, `0` is waiting for / denied access.
  final int status;
  final DateTime? createdAt;

  /// `users.xero_account_id` (Xero contact id); null when the user isn't linked to Xero.
  final String? xeroAccountId;

  const AdminUserRecord({
    required this.id,
    required this.email,
    required this.displayName,
    required this.companyName,
    required this.phoneNumber,
    required this.role,
    required this.status,
    required this.createdAt,
    this.xeroAccountId,
  });

  AdminUserRecord copyWith({int? role, int? status}) {
    return AdminUserRecord(
      id: id,
      email: email,
      displayName: displayName,
      companyName: companyName,
      phoneNumber: phoneNumber,
      role: role ?? this.role,
      status: status ?? this.status,
      createdAt: createdAt,
      xeroAccountId: xeroAccountId,
    );
  }
}

class AdminProductRecord {
  final String id;
  final String code;
  final String name;
  final String stock;
  final String price;
  final DateTime? updatedAt;

  const AdminProductRecord({
    required this.id,
    required this.code,
    required this.name,
    required this.stock,
    required this.price,
    required this.updatedAt,
  });
}

class AdminInvoiceRecord {
  final String id;
  final String number;
  final String customer;
  final String status;
  final String total;
  final String amountDue;
  final DateTime? issuedAt;

  const AdminInvoiceRecord({
    required this.id,
    required this.number,
    required this.customer,
    required this.status,
    required this.total,
    required this.amountDue,
    required this.issuedAt,
  });
}

class AdminAnnouncementRecord {
  final String id;
  final String title;
  final String body;
  final DateTime? createdAt;

  const AdminAnnouncementRecord({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });
}

class AdminPage<T> {
  final List<T> rows;
  final int total;

  const AdminPage({required this.rows, required this.total});
}

class AdminDashboardService {
  static const int pageSize = 20;

  /// [sortColumn] indexes the table's display columns: Name, Email, Company, Phone, Role, Status.
  /// A negative [sortColumn] means the default order: newest sign-ups first.
  static Future<AdminPage<AdminUserRecord>> listUsers({
    required int page,
    String query = '',
    int sortColumn = -1,
    bool ascending = false,
  }) async {
    // Older databases may lack `status` (migration 0008) or `role` (0005); missing
    // columns fall back to sorting by sign-up date.
    const attempts = <(String, List<String>)>[
      ('role, status', ['display_name', 'email', 'company_name', 'phone_number', 'role', 'status']),
      ('role', ['display_name', 'email', 'company_name', 'phone_number', 'role', 'created_at']),
      ('', ['display_name', 'email', 'company_name', 'phone_number', 'created_at', 'created_at']),
    ];
    Object? lastError;
    for (final (extra, columns) in attempts) {
      try {
        final result = await _fetchPage(
          table: 'users',
          select: 'id, email, display_name, company_name, phone_number, xero_account_id, created_at${extra.isEmpty ? '' : ', $extra'}',
          orderBy: sortColumn < 0 ? 'created_at' : _pick(columns, sortColumn),
          ascending: sortColumn < 0 ? false : ascending,
          tieBreaker: 'id',
          page: page,
          orFilter: _orIlike(query, const ['display_name', 'email', 'company_name', 'phone_number']),
        );
        return AdminPage(rows: result.rows.map(_userFromRow).toList(), total: result.total);
      } catch (e) {
        lastError = e;
        if (!_missingColumn(e)) rethrow;
      }
    }
    throw lastError ?? 'Unable to load users.';
  }

  /// Allows (1) or blocks (0) a user's login. Only admins can change it (enforced in the database).
  static Future<void> setUserStatus({required String userId, required int status}) async {
    await SupabaseService.update(
      'users',
      {
        'status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      filters: {'id': userId},
    );
  }

  static Future<void> setUserRole({required String userId, required int role}) async {
    await SupabaseService.update(
      'users',
      {
        'role': role,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      filters: {'id': userId},
    );
  }

  /// [sortColumn] indexes the display columns: Code, Name, On hand, Price, Updated.
  /// Password that [formatUserPassword] sets; must match migration 0007.
  static const String defaultPassword = '12345678';

  /// Make webhook that removes the user's account in Xero. Responds `true` on success.
  static const String _removeAccountWebhookUrl = 'https://hook.eu1.make.com/mdrecc2eivgk8m4x3njmk3vjlj263wi4';

  /// Removes a user's account (admin only, enforced in the database).
  ///
  /// Users linked to Xero: POST `{id: xero_account_id}` to Make first, and only delete when it
  /// answers `true`. Then delete the login (auth.users), which cascades to the users row.
  static Future<void> removeUserAccount(AdminUserRecord user) async {
    final xeroId = user.xeroAccountId?.trim() ?? '';
    if (xeroId.isNotEmpty) {
      final res = await http
          .post(
            Uri.parse(_removeAccountWebhookUrl),
            headers: const {
              'content-type': 'application/json; charset=utf-8',
              'accept': 'application/json',
            },
            body: jsonEncode({'id': xeroId}),
          )
          .timeout(const Duration(seconds: 25));
      final body = utf8.decode(res.bodyBytes);
      final ok = res.statusCode >= 200 && res.statusCode < 300 && _isTrueResponse(body);
      if (!ok) {
        final shown = body.trim().isEmpty ? 'status ${res.statusCode}' : body.trim();
        throw 'Xero did not confirm the removal (response: $shown). The account was not removed.';
      }
    }
    await SupabaseConfig.client.rpc('admin_delete_user', params: {'target_user_id': user.id});
  }

  /// `true` as plain text, JSON `true`/`"true"`, or a JSON object whose result/success/ok/deleted is true.
  static bool _isTrueResponse(String body) {
    bool isTrue(dynamic v) => v == true || v?.toString().trim().toLowerCase() == 'true';
    final text = body.trim();
    if (isTrue(text)) return true;
    try {
      final decoded = jsonDecode(text);
      if (isTrue(decoded)) return true;
      if (decoded is Map) {
        for (final key in decoded.keys) {
          if (const {'result', 'success', 'ok', 'deleted'}.contains(key.toString().toLowerCase()) && isTrue(decoded[key])) {
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  /// Resets a user's login password to [defaultPassword] (admin only, enforced in the database).
  static Future<void> formatUserPassword(String userId) async {
    await SupabaseConfig.client.rpc('admin_format_user_password', params: {'target_user_id': userId});
  }

  static Future<AdminPage<AdminProductRecord>> listProducts({
    required int page,
    String query = '',
    int sortColumn = 1,
    bool ascending = true,
  }) async {
    Object? lastError;
    final attempts = <_ProductAttempt>[
      _ProductAttempt(
        select: 'item_id, code, name, quantity_on_hand, sales_details, updated_date_utc',
        orderBy: _pick(const ['code', 'name', 'quantity_on_hand', 'sales_details->UnitPrice', 'updated_date_utc'], sortColumn),
        tieBreaker: 'item_id',
      ),
      _ProductAttempt(
        select: 'xero_item_id, code, name, sale_price_cents, description, updated_at',
        // The legacy schema has no stock column; On hand falls back to Name.
        orderBy: _pick(const ['code', 'name', 'name', 'sale_price_cents', 'updated_at'], sortColumn),
        tieBreaker: 'xero_item_id',
      ),
    ];
    for (final attempt in attempts) {
      try {
        final result = await _fetchPage(
          table: 'xero_products',
          select: attempt.select,
          orderBy: attempt.orderBy,
          ascending: ascending,
          tieBreaker: attempt.tieBreaker,
          page: page,
          orFilter: _orIlike(query, const ['name', 'code']),
        );
        return AdminPage(rows: result.rows.map(_productFromRow).toList(), total: result.total);
      } catch (e) {
        lastError = e;
        if (!_missingColumn(e) && !_missingTable(e)) rethrow;
      }
    }
    throw lastError ?? 'Unable to load products.';
  }

  /// Loads every column of one product row for the detail modal.
  static Future<Map<String, dynamic>> getProduct(String id) async {
    Object? lastError;
    for (final idColumn in const ['item_id', 'xero_item_id']) {
      try {
        final row = await SupabaseConfig.client.from('xero_products').select().eq(idColumn, id).maybeSingle();
        if (row != null) return row;
      } catch (e) {
        lastError = e;
        if (!_missingColumn(e)) rethrow;
      }
    }
    throw lastError ?? 'Product not found.';
  }

  /// [sortColumn] indexes the display columns: Number, Customer, Status, Total, Due, Issued.
  static Future<AdminPage<AdminInvoiceRecord>> listInvoices({
    required int page,
    String query = '',
    int sortColumn = 5,
    bool ascending = false,
  }) async {
    try {
      final result = await _fetchPage(
        table: 'invoice',
        select: 'invoice_id, invoice_num, status, total, amount_due, currency_code, date, contact',
        orderBy: _pick(const ['invoice_num', 'contact->>name', 'status', 'total', 'amount_due', 'date'], sortColumn),
        ascending: ascending,
        tieBreaker: 'invoice_id',
        page: page,
        // Customer name lives in the `contact` JSON ({contact_id, name}) written by the invoice sync.
        orFilter: _orIlike(query, const ['invoice_num', 'contact->>name', 'status']),
      );
      return AdminPage(rows: result.rows.map(_invoiceFromInvoiceTable).toList(), total: result.total);
    } catch (e) {
      if (!_missingColumn(e) && !_missingTable(e)) rethrow;
    }

    final result = await _fetchPage(
      table: 'xero_invoices',
      select: 'id, xero_invoice_id, invoice_number, contact_id, status, total, amount_due, currency, issue_date',
      orderBy: _pick(const ['invoice_number', 'contact_id', 'status', 'total', 'amount_due', 'issue_date'], sortColumn),
      ascending: ascending,
      tieBreaker: 'id',
      page: page,
      orFilter: _orIlike(query, const ['invoice_number', 'status', 'contact_id']),
    );
    return AdminPage(rows: result.rows.map(_invoiceFromXeroTable).toList(), total: result.total);
  }

  /// Loads every column of one invoice (including line items and payments) for the detail modal.
  /// [id] is `invoice.invoice_id`, or `xero_invoices.id` when the legacy table is in use.
  static Future<Map<String, dynamic>> getInvoice(String id) async {
    try {
      final row = await SupabaseConfig.client.from('invoice').select().eq('invoice_id', id).maybeSingle();
      if (row != null) return row;
    } catch (e) {
      if (!_missingColumn(e) && !_missingTable(e)) rethrow;
    }
    final legacy = await SupabaseConfig.client.from('xero_invoices').select().eq('id', id).maybeSingle();
    if (legacy == null) throw 'Invoice not found.';
    return legacy;
  }

  static Future<List<AdminAnnouncementRecord>> listAnnouncements() async {
    final rows = await SupabaseService.select(
      'announcements',
      select: 'id, title, body, created_at',
      orderBy: 'created_at',
      ascending: false,
      limit: 200,
    );
    return rows.map(_announcementFromRow).toList();
  }

  static Future<AdminAnnouncementRecord> createAnnouncement({
    required String title,
    required String body,
    required String createdBy,
  }) async {
    final rows = await SupabaseService.insert('announcements', {
      'title': title,
      'body': body,
      'created_by': createdBy,
    });
    if (rows.isEmpty) {
      return AdminAnnouncementRecord(id: '', title: title, body: body, createdAt: DateTime.now().toUtc());
    }
    return _announcementFromRow(rows.first);
  }

  static Future<void> deleteAnnouncement(String id) async {
    await SupabaseService.delete('announcements', filters: {'id': id});
  }

  static Future<({List<Map<String, dynamic>> rows, int total})> _fetchPage({
    required String table,
    required String select,
    required String orderBy,
    required bool ascending,
    required int page,
    String? tieBreaker,
    String? orFilter,
    String? eqColumn,
    Object? eqValue,
  }) async {
    final from = page * pageSize;
    final to = from + pageSize - 1;
    dynamic query = SupabaseConfig.client.from(table).select(select);
    if (eqColumn != null) query = query.eq(eqColumn, eqValue);
    if (orFilter != null && orFilter.isNotEmpty) query = query.or(orFilter);
    query = query.order(orderBy, ascending: ascending);
    // A unique secondary key keeps page boundaries stable when sort values repeat.
    if (tieBreaker != null) query = query.order(tieBreaker, ascending: true);
    query = query.range(from, to);
    final res = await query.count(CountOption.exact);
    final data = (res.data as List?) ?? const <dynamic>[];
    final rows = data.cast<Map<String, dynamic>>();
    final count = res.count;
    return (rows: rows, total: count is int ? count : rows.length);
  }

  /// Maps a display column index to its database column.
  static String _pick(List<String> columns, int index) => columns[index.clamp(0, columns.length - 1)];

  static String? _orIlike(String query, List<String> columns) {
    final cleaned = query.trim().replaceAll(RegExp(r'[%*,()"]'), ' ').trim();
    if (cleaned.isEmpty || columns.isEmpty) return null;
    final pattern = '"%$cleaned%"';
    return columns.map((column) => '$column.ilike.$pattern').join(',');
  }

  static AdminUserRecord _userFromRow(Map<String, dynamic> row) {
    return AdminUserRecord(
      id: _text(row['id']),
      email: _text(row['email'], fallback: '—'),
      displayName: _text(row['display_name'], fallback: '—'),
      companyName: _text(row['company_name'], fallback: '—'),
      phoneNumber: _text(row['phone_number'], fallback: '—'),
      role: _int(row['role']),
      // No status column yet (before migration 0008) means everyone may log in.
      status: row['status'] == null ? 1 : _int(row['status']),
      createdAt: _date(row['created_at']),
      xeroAccountId: _text(row['xero_account_id'], fallback: '') == '' ? null : _text(row['xero_account_id']),
    );
  }

  static AdminProductRecord _productFromRow(Map<String, dynamic> row) {
    final rawId = row['item_id'] ?? row['xero_item_id'];
    final id = _text(rawId);
    final cents = row['sale_price_cents'];
    final price = cents is num ? (cents / 100).toStringAsFixed(2) : _unitPrice(row['sales_details']);
    final stock = row['quantity_on_hand'];
    return AdminProductRecord(
      id: id,
      code: _text(row['code'], fallback: '—'),
      name: _text(row['name'], fallback: '—'),
      stock: stock == null ? '—' : _text(stock),
      price: price,
      updatedAt: _date(row['updated_date_utc'] ?? row['updated_at']),
    );
  }

  static AdminInvoiceRecord _invoiceFromInvoiceTable(Map<String, dynamic> row) {
    final currency = _text(row['currency_code']);
    return AdminInvoiceRecord(
      id: _text(row['invoice_id']),
      number: _text(row['invoice_num'], fallback: _text(row['invoice_id'], fallback: '—')),
      customer: _contactName(row['contact']),
      status: _text(row['status'], fallback: '—'),
      total: _money(row['total'], currency),
      amountDue: _money(row['amount_due'], currency),
      issuedAt: _date(row['date']),
    );
  }

  static AdminInvoiceRecord _invoiceFromXeroTable(Map<String, dynamic> row) {
    final currency = _text(row['currency']);
    final number = _text(row['invoice_number']);
    return AdminInvoiceRecord(
      id: _text(row['id']),
      number: number == '—' ? _text(row['xero_invoice_id'], fallback: '—') : number,
      customer: _text(row['contact_id'], fallback: '—'),
      status: _text(row['status'], fallback: '—'),
      total: _money(row['total'], currency),
      amountDue: _money(row['amount_due'], currency),
      issuedAt: _date(row['issue_date']),
    );
  }

  static AdminAnnouncementRecord _announcementFromRow(Map<String, dynamic> row) {
    return AdminAnnouncementRecord(
      id: _text(row['id']),
      title: _text(row['title'], fallback: 'Untitled'),
      body: _text(row['body']),
      createdAt: _date(row['created_at']),
    );
  }

  static String _contactName(dynamic contact) {
    if (contact is Map) {
      final name = contact['name'] ?? contact['Name'];
      final text = _text(name);
      if (text != '—') return text;
    }
    return '—';
  }

  static String _unitPrice(dynamic sales) {
    if (sales is Map) {
      final value = sales['UnitPrice'] ?? sales['unit_price'] ?? sales['unitPrice'];
      if (value is num) return value.toStringAsFixed(2);
      final parsed = double.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed.toStringAsFixed(2);
    }
    return '—';
  }

  static String _money(dynamic value, String currency) {
    final number = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
    if (number == null) return '—';
    final amount = number.toStringAsFixed(2);
    return currency.isEmpty || currency == '—' ? amount : '$currency $amount';
  }

  static String _text(dynamic value, {String fallback = '—'}) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null') return fallback;
    return text;
  }

  static int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  // Supabase stores UTC; strings without an offset must not be read as device-local time.
  static DateTime? _date(dynamic value) {
    return AppTime.parseUtc(value);
  }

  static bool _missingColumn(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('column') || message.contains('schema cache') || message.contains('42703');
  }

  static bool _missingTable(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('does not exist') || message.contains('42p01') || message.contains('schema cache');
  }
}

class _ProductAttempt {
  final String select;
  final String orderBy;
  final String tieBreaker;
  const _ProductAttempt({required this.select, required this.orderBy, required this.tieBreaker});
}
