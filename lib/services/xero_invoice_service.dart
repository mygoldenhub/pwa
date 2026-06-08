import 'package:flutter/foundation.dart';
import 'package:pwa/models/xero_invoice.dart';
import 'package:pwa/supabase/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class XeroInvoiceService {
  static const String _invoiceListOrderPrimary = 'updated_date_utc';
  static const String _invoiceListOrderSecondary = 'date';
  static const String _invoiceListOrderTertiary = 'invoice_id';

  static dynamic _applyInvoiceListOrdering(dynamic q) => q
      // Stable ordering is critical for offset pagination.
      // We order by updated UTC timestamp first (newest first), then by invoice date,
      // then by invoice_id as a deterministic tie-breaker.
      .order(_invoiceListOrderPrimary, ascending: false)
      .order(_invoiceListOrderSecondary, ascending: false)
      .order(_invoiceListOrderTertiary, ascending: false);

  static Future<String?> _getMyXeroContactId() async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return null;
    try {
      final row = await SupabaseService.selectSingle(
        'users',
        select: 'xero_account_id',
        filters: {'id': user.id},
      );
      final v = row?['xero_account_id'];
      final id = v?.toString().trim() ?? '';
      return id.isEmpty ? null : id;
    } catch (e) {
      debugPrint('XeroInvoiceService: failed to load my xero_account_id: $e');
      return null;
    }
  }

  static String? _extractContactIdFromContactJson(dynamic contact) {
    if (contact is! Map) return null;
    final candidates = <String>['contact_id', 'ContactID', 'id', 'ID'];
    for (final k in candidates) {
      final v = contact[k];
      final s = v?.toString().trim() ?? '';
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static bool _isMissingColumnOrJsonKey(PostgrestException e) {
    final code = (e.code ?? '').toString();
    final msg = e.message.toLowerCase();
    // 42703 = undefined_column
    // PostgREST can also surface “does not exist” messages.
    return code == '42703' || msg.contains('does not exist') || msg.contains('undefined column');
  }

  static Future<List<Map<String, dynamic>>> _fetchInvoicesForContactId({
    required String contactId,
    required int limit,
    required int offset,
  }) async {
    // Keep the select aligned with `lib/models/xero_invoice.dart`.
    // We intentionally avoid selecting large JSON arrays (payments/line_items)
    // for list screens.
    const select =
        'invoice_id, type, invoice_num, reference, amount_due, amount_paid, amount_credited, '
        'currency_rate, is_discounted, has_attachments, contact, date_string, date, due_date_string, '
        'due_date, status, line_amount_types, sub_total, total_tax, total, updated_date_utc, '
        'currency_code, full_paid_on_date';
    // Attempt 1: if a `contact_id` column exists, use it (fast + indexed).
    try {
      final q = SupabaseService.from('invoice').select(select).eq('contact_id', contactId);
      final res = await _applyInvoiceListOrdering(q).range(offset, offset + limit - 1);
      final rows = (res as List).cast<Map<String, dynamic>>();
      debugPrint('XeroInvoiceService: invoice.contact_id filter rows=${rows.length}');
      if (rows.isNotEmpty) return rows;
    } on PostgrestException catch (e) {
      if (!_isMissingColumnOrJsonKey(e)) rethrow;
      debugPrint('XeroInvoiceService: contact_id column not available; falling back to contact JSON. (${e.code})');
    }

    // Attempt 2+: common JSON key variants.
    final jsonKeys = <String>['contact_id', 'ContactID', 'id', 'ID'];
    for (final key in jsonKeys) {
      try {
        final q = SupabaseService.from('invoice').select(select).eq('contact->>$key', contactId);
        final res = await _applyInvoiceListOrdering(q).range(offset, offset + limit - 1);
        final rows = (res as List).cast<Map<String, dynamic>>();
        debugPrint('XeroInvoiceService: invoice.contact->>$key filter rows=${rows.length}');
        if (rows.isNotEmpty) return rows;
      } on PostgrestException catch (e) {
        // If the JSON key doesn't exist, Postgres doesn't error; it just returns 0 rows.
        // But some setups can error on JSON path expressions; keep it tolerant.
        if (!_isMissingColumnOrJsonKey(e)) rethrow;
        debugPrint('XeroInvoiceService: contact->>$key not supported; trying next key. (${e.code})');
      }
    }

    // Final fallback: fetch visible invoices and filter client-side by contact json.
    // This still respects RLS and still only shows *this* customer's invoices.
    final fallbackQ = SupabaseService.from('invoice').select(select);
    final fallbackRes = await _applyInvoiceListOrdering(fallbackQ).range(offset, offset + limit - 1);
    final allRows = (fallbackRes as List).cast<Map<String, dynamic>>();
    debugPrint('XeroInvoiceService: fallback unfiltered visible rows=${allRows.length}');
    return allRows.where((r) {
      final extracted = _extractContactIdFromContactJson(r['contact']);
      return extracted == contactId;
    }).toList();
  }

  static Future<List<XeroInvoice>> listMyInvoices({int limit = 50}) async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) {
      debugPrint('XeroInvoiceService: listMyInvoices called with no signed-in user');
      return <XeroInvoice>[];
    }

    final contactId = await _getMyXeroContactId();
    debugPrint('XeroInvoiceService: listMyInvoices for user=${user.id} contactId=${contactId ?? '(null)'}');

    try {
      final id = contactId?.trim();
      if (id == null || id.isEmpty) {
        debugPrint('XeroInvoiceService: no xero_account_id found for user; returning empty invoice list');
        return <XeroInvoice>[];
      }

      final rows = await _fetchInvoicesForContactId(contactId: id, limit: limit, offset: 0);
      debugPrint('XeroInvoiceService: fetched ${rows.length} invoice rows');

      final invoices = rows.map(XeroInvoice.fromJson).whereType<XeroInvoice>().toList();
      debugPrint('XeroInvoiceService: parsed ${invoices.length} invoices');
      return invoices;
    } catch (e) {
      debugPrint('XeroInvoiceService: listMyInvoices failed: $e');
      rethrow;
    }
  }

  static Future<List<XeroInvoice>> listMyInvoicesPage({required int pageSize, required int offset}) async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) {
      debugPrint('XeroInvoiceService: listMyInvoicesPage called with no signed-in user');
      return <XeroInvoice>[];
    }

    final contactId = await _getMyXeroContactId();
    debugPrint('XeroInvoiceService: listMyInvoicesPage user=${user.id} contactId=${contactId ?? '(null)'} offset=$offset size=$pageSize');

    try {
      final id = contactId?.trim();
      if (id == null || id.isEmpty) {
        debugPrint('XeroInvoiceService: no xero_account_id found for user; returning empty invoice page');
        return <XeroInvoice>[];
      }

      final rows = await _fetchInvoicesForContactId(contactId: id, limit: pageSize, offset: offset);
      final invoices = rows.map(XeroInvoice.fromJson).whereType<XeroInvoice>().toList();
      return invoices;
    } catch (e) {
      debugPrint('XeroInvoiceService: listMyInvoicesPage failed: $e');
      rethrow;
    }
  }

  /// Fetch a single invoice including heavy JSON arrays (`payments`, `line_items`).
  ///
  /// Use this for details screens / modals, not list views.
  static Future<XeroInvoice?> getMyInvoiceDetails({required String invoiceId}) async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) {
      debugPrint('XeroInvoiceService: getMyInvoiceDetails called with no signed-in user');
      return null;
    }

    final id = invoiceId.trim();
    if (id.isEmpty) return null;

    // Keep aligned with `lib/models/xero_invoice.dart`.
    const select =
        'invoice_id, type, invoice_num, reference, amount_due, amount_paid, amount_credited, '
        'currency_rate, is_discounted, has_attachments, contact, date_string, date, due_date_string, '
        'due_date, status, line_amount_types, sub_total, total_tax, total, updated_date_utc, '
        'currency_code, full_paid_on_date, payments, line_items';

    try {
      final row = await SupabaseService.selectSingle('invoice', select: select, filters: {'invoice_id': id});
      final invoice = XeroInvoice.fromJson(row);
      return invoice;
    } catch (e) {
      debugPrint('XeroInvoiceService: getMyInvoiceDetails failed invoice_id=$invoiceId: $e');
      rethrow;
    }
  }
}
