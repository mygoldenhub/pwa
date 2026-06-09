import 'package:flutter/foundation.dart';
import 'package:pwa/models/xero_product.dart';
import 'package:pwa/supabase/supabase_config.dart';

class XeroProductService {
  static const String _table = 'xero_products';
  static bool _didLogDiagnostics = false;

  // The xero_products schema has evolved over time.
  // New schema (2026): item_id, code, name, description, quantity_on_hand,
  // sales_details (jsonb), purchase_details (jsonb), updated_date_utc
  // Old schema: xero_item_id, sale_price_cents, sales_account, tax_rate, created_at, updated_at
  static const String _selectFullNew =
      'item_id, code, name, description, quantity_on_hand, sales_details, purchase_details, updated_date_utc';
  static const String _selectMinimalNew = 'item_id, code, name, updated_date_utc';

  static const String _selectFullOld =
      'xero_item_id, code, name, sale_price_cents, sales_account, tax_rate, description, created_at, updated_at';
  static const String _selectMinimalOld = 'xero_item_id, code, name, created_at, updated_at';

  static bool _looksLikeMissingColumnOrCache(dynamic e) {
    final s = e.toString().toLowerCase();
    return s.contains('schema cache') || s.contains('could not find the') || s.contains('column');
  }

  static Future<List<Map<String, dynamic>>> _safeSearch(
    String like, {
    required int limit,
  }) async {
    Future<List<Map<String, dynamic>>> run(String select) async {
      final res = await SupabaseService.from(_table)
          .select(select)
          .ilike('name', like)
          .order('name', ascending: true)
          .limit(limit);
      return (res as List).cast<Map<String, dynamic>>();
    }

    // Prefer new schema; fall back to old schema; then fall back to minimal.
    try {
      return await run(_selectFullNew);
    } catch (e) {
      if (!_looksLikeMissingColumnOrCache(e)) rethrow;
      debugPrint('XeroProductService: new-schema full select failed; trying old schema. Error: $e');
    }

    try {
      return await run(_selectFullOld);
    } catch (e) {
      if (!_looksLikeMissingColumnOrCache(e)) rethrow;
      debugPrint('XeroProductService: old-schema full select failed; trying minimal selects. Error: $e');
    }

    try {
      return await run(_selectMinimalNew);
    } catch (e) {
      if (!_looksLikeMissingColumnOrCache(e)) rethrow;
      debugPrint('XeroProductService: new-schema minimal select failed; trying old minimal. Error: $e');
      return await run(_selectMinimalOld);
    }
  }

  static Future<List<Map<String, dynamic>>> _safeSearchAllTokens(
    List<String> tokens, {
    required int limit,
  }) async {
    if (tokens.isEmpty) return [];

    Future<List<Map<String, dynamic>>> run(String select) async {
      var q = SupabaseService.from(_table).select(select);
      // AND-match all tokens, order-independent.
      for (final t in tokens) {
        q = q.ilike('name', '%$t%');
      }
      final res = await q.order('name', ascending: true).limit(limit);
      return (res as List).cast<Map<String, dynamic>>();
    }

    // Prefer new schema; fall back to old schema; then fall back to minimal.
    try {
      return await run(_selectFullNew);
    } catch (e) {
      if (!_looksLikeMissingColumnOrCache(e)) rethrow;
      debugPrint('XeroProductService: new-schema token search failed; trying old schema. Error: $e');
    }

    try {
      return await run(_selectFullOld);
    } catch (e) {
      if (!_looksLikeMissingColumnOrCache(e)) rethrow;
      debugPrint('XeroProductService: old-schema token search failed; trying minimal selects. Error: $e');
    }

    try {
      return await run(_selectMinimalNew);
    } catch (e) {
      if (!_looksLikeMissingColumnOrCache(e)) rethrow;
      debugPrint('XeroProductService: new-schema minimal token search failed; trying old minimal. Error: $e');
      return await run(_selectMinimalOld);
    }
  }

  static Future<Map<String, dynamic>?> _safeGetSingle({String? xeroItemId, String? code}) async {
    if ((xeroItemId == null || xeroItemId.isEmpty) && (code == null || code.isEmpty)) return null;

    Future<Map<String, dynamic>?> runNewId(String select) async {
      var q = SupabaseService.from(_table).select(select);
      if (xeroItemId != null && xeroItemId.isNotEmpty) q = q.eq('item_id', xeroItemId);
      if (code != null && code.isNotEmpty) q = q.eq('code', code);
      final res = await q.maybeSingle();
      if (res == null) return null;
      return (res as Map).cast<String, dynamic>();
    }

    Future<Map<String, dynamic>?> runOldId(String select) async {
      var q = SupabaseService.from(_table).select(select);
      if (xeroItemId != null && xeroItemId.isNotEmpty) q = q.eq('xero_item_id', xeroItemId);
      if (code != null && code.isNotEmpty) q = q.eq('code', code);
      final res = await q.maybeSingle();
      if (res == null) return null;
      return (res as Map).cast<String, dynamic>();
    }

    Future<Map<String, dynamic>?> run(String select) async {
      // IMPORTANT: do not reference columns that may not exist.
      // Your current table uses `item_id` as the PK and does NOT have `xero_item_id`.
      // If we build an `or(item_id.eq...,xero_item_id.eq...)` filter, PostgREST errors.
      try {
        return await runNewId(select);
      } catch (e) {
        if (!_looksLikeMissingColumnOrCache(e)) rethrow;
        debugPrint('XeroProductService: item_id filter failed; trying legacy xero_item_id. Error: $e');
        return await runOldId(select);
      }
    }

    try {
      return await run(_selectFullNew);
    } catch (e) {
      if (!_looksLikeMissingColumnOrCache(e)) rethrow;
      debugPrint('XeroProductService: new-schema getSingle failed; trying old schema. Error: $e');
    }

    try {
      return await run(_selectFullOld);
    } catch (e) {
      if (!_looksLikeMissingColumnOrCache(e)) rethrow;
      debugPrint('XeroProductService: old-schema getSingle failed; trying minimal selects. Error: $e');
    }

    try {
      return await run(_selectMinimalNew);
    } catch (e) {
      if (!_looksLikeMissingColumnOrCache(e)) rethrow;
      debugPrint('XeroProductService: new-schema minimal getSingle failed; trying old minimal. Error: $e');
      return await run(_selectMinimalOld);
    }
  }

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

    // If the user typed multiple keywords, do order-independent AND matching.
    // Example: "ex se silicon travertine" should match names containing all
    // tokens, regardless of order.
    final tokens = _tokenizeQuery(q);
    if (tokens.length >= 2) return _searchByAllTokens(tokens, limit: limit, rawQueryForDiagnostics: q);

    try {
      // PostgREST `or()` uses comma-separated filters.
      // We intentionally do not escape %/_ here; users rarely type them and
      // treating them as wildcards is acceptable for search UX.
      final prefixLike = '${q}%';
      final containsLike = '%${q}%';

      final prefixRows = await _safeSearch(prefixLike, limit: limit);
      final prefixParsed = prefixRows
          .map(XeroProduct.fromRow)
          .where((p) => p.xeroItemId.isNotEmpty && p.name.trim().isNotEmpty)
          .toList();

      if (prefixParsed.length >= limit) return prefixParsed;

      final remaining = limit - prefixParsed.length;
      final containsRows = await _safeSearch(containsLike, limit: limit);
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

  static Future<List<XeroProduct>> _searchByAllTokens(
    List<String> tokens, {
    required int limit,
    required String rawQueryForDiagnostics,
  }) async {
    try {
      final rows = await _safeSearchAllTokens(tokens, limit: limit);
      final parsed = rows
          .map(XeroProduct.fromRow)
          .where((p) => p.xeroItemId.isNotEmpty && p.name.trim().isNotEmpty)
          .toList();

      if (parsed.isEmpty) {
        await _logDiagnosticsOnce(query: rawQueryForDiagnostics);
      }
      return parsed;
    } catch (e) {
      debugPrint('XeroProductService token search failed (query="$rawQueryForDiagnostics", tokens=$tokens): $e');
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

  static List<String> _tokenizeQuery(String normalizedPhrase) {
    final tokens = normalizedPhrase
        .split(' ')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    // De-dupe while preserving order.
    final seen = <String>{};
    return tokens.where(seen.add).toList();
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
      dynamic sample;
      try {
        sample = await SupabaseService.from(_table).select('item_id, name').limit(1);
      } catch (e) {
        sample = await SupabaseService.from(_table).select('xero_item_id, name').limit(1);
      }
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
      final row = await _safeGetSingle(xeroItemId: id);
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
      final row = await _safeGetSingle(code: c);
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
