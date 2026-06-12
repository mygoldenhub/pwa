import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores a pending, already-shaped invoice payload locally (JSON string).
///
/// This enables the flow:
/// Cart -> Pay now -> Stripe checkout -> (return) -> POST invoice payload to Make.
class PendingInvoiceStorage {
  static const String _key = 'pending_invoice_payload_v1';

  static Future<void> save(Map<String, dynamic> payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(payload);
      await prefs.setString(_key, jsonStr);
    } catch (e) {
      debugPrint('PendingInvoiceStorage.save failed: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
      return null;
    } catch (e) {
      debugPrint('PendingInvoiceStorage.load failed: $e');
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (e) {
      debugPrint('PendingInvoiceStorage.clear failed: $e');
    }
  }

  /// Loads and clears the pending payload.
  ///
  /// If parsing fails, it returns null and clears the value to prevent
  /// repeated failures.
  static Future<Map<String, dynamic>?> take() async {
    final payload = await load();
    if (payload == null) {
      await clear();
      return null;
    }
    await clear();
    return payload;
  }
}
