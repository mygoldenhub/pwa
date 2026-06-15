import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores a pending payload for the flow:
/// Invoice -> Pay now -> Stripe checkout -> (return) -> POST payment payload to Make.
///
/// This is intentionally separate from [PendingInvoiceStorage] (cart -> create invoice)
/// so the two flows don't clobber each other.
class PendingInvoicePaymentStorage {
  static const String _key = 'pending_invoice_payment_payload_v1';

  static Future<void> save(Map<String, dynamic> payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(payload));
    } catch (e) {
      debugPrint('PendingInvoicePaymentStorage.save failed: $e');
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
      debugPrint('PendingInvoicePaymentStorage.load failed: $e');
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (e) {
      debugPrint('PendingInvoicePaymentStorage.clear failed: $e');
    }
  }

  static Future<Map<String, dynamic>?> take() async {
    final payload = await load();
    await clear();
    return payload;
  }
}
