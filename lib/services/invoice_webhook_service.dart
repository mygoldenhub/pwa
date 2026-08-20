import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pwa/components/new_invoice_sheet.dart';
import 'package:pwa/models/cart_item.dart';
import 'package:pwa/models/xero_product.dart';

class InvoiceWebhookService {
  /// Direct Make.com webhook URL for creating invoices.
  ///
  /// Per your request, this is hardcoded (no `.env`, no `--dart-define`).
  static const String _webhookUrl = 'https://hook.eu1.make.com/ql9bxv2lrgo4cmdj2wo34wy23wcumcuf';

  static Uri _webhookUri() => Uri.parse(_webhookUrl);

  static String lineAmountTypeApi(LineAmountType t) => switch (t) {
        LineAmountType.exclusive => 'Exclusive',
        LineAmountType.inclusive => 'Inclusive',
        LineAmountType.noTax => 'NoTax',
      };

  static String fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static dynamic _accountCodeValue(XeroProduct? p) {
    final raw = p?.salesAccount?.trim();
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw) ?? raw;
  }

  /// Calls the external webhook to create a new invoice.
  ///
  /// [productsByItemId] should contain entries for cart `xero_item_id`s.
  /// If a product is missing, we still send a best-effort line item using
  /// values available on the cart row.
  static Future<InvoiceWebhookResult> createInvoice({
    required InvoiceDraft draft,
    required List<CartItem> cartItems,
    required Map<String, XeroProduct?> productsByItemId,
    required String contactId,
  }) async {
    if (contactId.trim().isEmpty) throw 'Missing contactID (users.xero_account_id).';
    if (cartItems.isEmpty) throw 'Your cart is empty.';

    final payload = <String, dynamic>{
      'reference': draft.reference,
      'currency_code': draft.currencyCode,
      'currency_rate': draft.currencyRate,
      'line_amount_type': lineAmountTypeApi(draft.lineAmountType),
      'date': fmtDate(draft.date),
      'due_date': fmtDate(draft.dueDate),
      'contactID': contactId.trim(),
      'products': cartItems.map((c) {
        final p = productsByItemId[c.xeroItemId];
        // IMPORTANT: Webhook expects the customer's cart values.
        // - item: cart_items.product_name
        // - quantity: cart_items.quantity
        // - unit amount: cart_items.unit_price_cents (dollars)
        // Our CartItem model stores unitPriceCents internally as integer cents.
        final unitAmount = (c.unitPriceCents ?? 0) / 100.0;
        return <String, dynamic>{
          // Match the expected shape:
          // {
          //   description: "...",
          //   quantity: 4,
          //   unit amount: 10.5,
          //   item: "..."
          // }
          'description': (p?.description?.trim().isNotEmpty ?? false) ? p!.description : c.productName,
          'quantity': c.quantity,
          'unit amount': unitAmount,
          'item': c.productName,
          // xero_products.sales_details.AccountCode
          // Webhook expects key name with a space: "account code".
          'account code': _accountCodeValue(p),
        };
      }).toList(),
    };

    return submitInvoicePayload(payload);
  }

  /// Posts an already-shaped payload to the Make webhook.
  ///
  /// This is used by the "Pay now" flow: we store the cart/draft payload before
  /// Stripe checkout, then post it after Stripe returns successfully.
  static Future<InvoiceWebhookResult> submitInvoicePayload(
    Map<String, dynamic> payload, {
    bool markPaid = false,
  }) async {
    final uri = _webhookUri();

    final effectivePayload = <String, dynamic>{
      ...payload,
      if (markPaid) 'pay': 'paid',
    };

    try {
      debugPrint("--------------------------------------------------");
      final res = await http
          .post(
            uri,
            headers: const {
              'content-type': 'application/json; charset=utf-8',
              'accept': 'application/json',
            },
            body: jsonEncode(effectivePayload),
          )
          .timeout(const Duration(seconds: 25));

      final ok = res.statusCode >= 200 && res.statusCode < 300;
      debugPrint('--------Invoice ID--------');
      debugPrint('$res');
      debugPrint('--------Invoice ID--------');
      if (!ok) {
        debugPrint('InvoiceWebhookService.createInvoice failed: status=${res.statusCode} body=${res.body}');
        throw 'Webhook failed (${res.statusCode}). ${res.body.isEmpty ? 'No response body.' : res.body}';
      }
      debugPrint("--------------------------------------------------");

      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(res.bodyBytes));
        debugPrint('--------Invoice ID(decoded)--------');
        debugPrint('$decoded');
        debugPrint('--------Invoice ID--------');

      } catch (_) {
        decoded = utf8.decode(res.bodyBytes);
      }
      return InvoiceWebhookResult(statusCode: res.statusCode, body: decoded);
    } catch (e) {
      debugPrint('InvoiceWebhookService.createInvoice error: $e');
      rethrow;
    }
  }
}

class InvoiceWebhookResult {
  final int statusCode;
  final dynamic body;
  const InvoiceWebhookResult({required this.statusCode, required this.body});
}
