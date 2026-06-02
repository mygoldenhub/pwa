import 'package:flutter/foundation.dart';
import 'package:pwa/models/xero_product.dart';
import 'package:pwa/supabase/supabase_config.dart';

class XeroProductService {
  static const String _table = 'xero_products';
  static bool _didLogDiagnostics = false;

  /// Search Xero products for typeahead UI.
  ///
  /// Behavior:
  /// - Prioritizes **exact phrase prefix** matches first (case-insensitive):
  ///   - `name ILIKE '<query>%'
  /// - If there are not enough results, it falls back to **contains** matches:
  ///   - `name ILIKE '%<query>%'
  ///
  /// This ensures that when a user types e.g. "MAPEI", the first suggestions
  /// are products that start with "MAPEI" (if any exist).
  static Future<List<XeroProduct>> searchByNamePrefix(String query, {int limit = 8}) async {
    final q = _normalizePhraseQuery(query);
    if (q.isEmpty) return [];

    try {
      // PostgREST `or()` uses comma-separated filters.
      // We intentionally do not escape %/_ here; users rarely type them and
      // treating them as wildcards is acceptable for search UX.
      final select = 'xero_item_id, code, name, sale_price_cents, sales_account, tax_rate, description, created_at, updated_at';

      final prefixLike = '${q}%';
      final containsLike = '%${q}%';

      final prefixRes = await SupabaseService.from(_table)
          .select(select)
          .ilike('name', prefixLike)
          .order('name', ascending: true)
          .limit(limit);

      final prefixRows = (prefixRes as List).cast<Map<String, dynamic>>();
      final prefixParsed = prefixRows
          .map(XeroProduct.fromRow)
          .where((p) => p.xeroItemId.isNotEmpty && p.name.trim().isNotEmpty)
          .toList();

      if (prefixParsed.length >= limit) return prefixParsed;

      final remaining = limit - prefixParsed.length;
      final containsRes = await SupabaseService.from(_table)
          .select(select)
          .ilike('name', containsLike)
          .order('name', ascending: true)
          .limit(limit);

      final containsRows = (containsRes as List).cast<Map<String, dynamic>>();
      final containsParsed = containsRows
          .map(XeroProduct.fromRow)
          .where((p) => p.xeroItemId.isNotEmpty && p.name.trim().isNotEmpty)
          .toList();

      final merged = _mergeUniqueById(prefixParsed, containsParsed).take(limit).toList();

      // If we consistently get 0 results, it might be because:
      // - xero_sync_products hasn't populated the table yet, OR
      // - RLS is enabled and there's no SELECT policy for the current role.
      // Log a one-time diagnostic to help differentiate.
      if (merged.isEmpty) {
        await _logDiagnosticsOnce(query: q);
      }
      return merged;
    } catch (e) {
      debugPrint('XeroProductService.searchByNamePrefix failed (query="$q"): $e');
      return [];
    }
  }

  static String _normalizePhraseQuery(String raw) {
    // Keep the user's phrase intact (spaces matter for "exact phrase" intent),
    // but trim and collapse repeated whitespace.
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceAll(RegExp(r'\s+'), ' ');
  }

  static Iterable<XeroProduct> _mergeUniqueById(List<XeroProduct> first, List<XeroProduct> second) sync* {
    final seen = <String>{};
    for (final p in first) {
      if (p.xeroItemId.isEmpty) continue;
      if (seen.add(p.xeroItemId)) yield p;
    }
    for (final p in second) {
      if (p.xeroItemId.isEmpty) continue;
      if (seen.add(p.xeroItemId)) yield p;
    }
  }

  // Note: previously this service implemented an "ordered subsequence" matcher
  // ("%m%a%p%e%i%") which is great for fuzzy search, but it does NOT satisfy
  // the "exact phrase starts-with" requirement.

  static Future<void> _logDiagnosticsOnce({required String query}) async {
    if (_didLogDiagnostics) return;
    _didLogDiagnostics = true;
    try {
      final session = SupabaseConfig.auth.currentSession;
      debugPrint('XeroProductService: 0 matches for "$query". signedIn=${session != null}. userId=${session?.user.id}');

      // Try to read any row at all. If RLS blocks SELECT, this often returns an empty list.
      final sample = await SupabaseService.from(_table).select('xero_item_id, name').limit(1);
      final sampleRows = (sample as List).cast<Map<String, dynamic>>();
      debugPrint('XeroProductService: sample read xero_products rows=${sampleRows.length}');
      if (sampleRows.isEmpty) {
        debugPrint(
          'XeroProductService: xero_products returned 0 rows even for limit(1). If you expect data, check Supabase RLS policies for public.xero_products (allow authenticated SELECT), and confirm xero_sync_products has inserted rows.',
        );
      } else {
        debugPrint('XeroProductService: example row name="${sampleRows.first['name']}"');
      }
    } catch (e) {
      debugPrint('XeroProductService diagnostics failed: $e');
    }
  }

  static Future<XeroProduct?> getByXeroItemId(String xeroItemId) async {
    final id = xeroItemId.trim();
    if (id.isEmpty) return null;
    try {
      final row = await SupabaseService.selectSingle(
        _table,
        select: 'xero_item_id, code, name, sale_price_cents, sales_account, tax_rate, description, created_at, updated_at',
        filters: {'xero_item_id': id},
      );
      if (row == null) return null;
      final p = XeroProduct.fromRow(row);
      return p.xeroItemId.isEmpty ? null : p;
    } catch (e) {
      debugPrint('XeroProductService.getByXeroItemId failed: $e');
      return null;
    }
  }

  static Future<XeroProduct?> getByCode(String code) async {
    final c = code.trim();
    if (c.isEmpty) return null;
    try {
      final row = await SupabaseService.selectSingle(
        _table,
        select: 'xero_item_id, code, name, sale_price_cents, sales_account, tax_rate, description, created_at, updated_at',
        filters: {'code': c},
      );
      if (row == null) return null;
      final p = XeroProduct.fromRow(row);
      return p.xeroItemId.isEmpty ? null : p;
    } catch (e) {
      debugPrint('XeroProductService.getByCode failed: $e');
      return null;
    }
  }

  // Intentionally no LIKE escaping helper; see note in searchByNamePrefix.
}
