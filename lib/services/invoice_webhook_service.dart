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
      return InvoiceWebhookResult.fromResponse(statusCode: res.statusCode, body: decoded);
    } catch (e) {
      debugPrint('InvoiceWebhookService.createInvoice error: $e');
      rethrow;
    }
  }
}

class InvoiceWebhookResult {
  final int statusCode;
  final dynamic body;

  /// Parsed invoice id from either a plain string body or `{ invoiceid, discount }`.
  final String? invoiceId;

  /// Trade discount percent from the webhook (e.g. `20` means 20%).
  final double? discountPercent;

  static final RegExp _uuidPattern = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  );

  static final RegExp _invoiceIdInText = RegExp(
    r'invoice[_ ]?id["\s:=]+["\s]*([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})',
    caseSensitive: false,
  );

  static final RegExp _discountInText = RegExp(
    r'discount["\s:=]+["\s]*([0-9]+(?:\.[0-9]+)?)',
    caseSensitive: false,
  );

  const InvoiceWebhookResult({
    required this.statusCode,
    required this.body,
    this.invoiceId,
    this.discountPercent,
  });

  factory InvoiceWebhookResult.fromResponse({
    required int statusCode,
    required dynamic body,
  }) {
    dynamic parsed = body;

    // Make sometimes returns a JSON object as a quoted/unquoted string.
    if (parsed is String) {
      final trimmed = parsed.trim();
      if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
          (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
        try {
          parsed = jsonDecode(trimmed);
        } catch (_) {
          // Keep as string — Make often returns JS-like objects without quotes.
        }
      }
    }

    String? invoiceId;
    double? discountPercent;

    if (parsed is Map) {
      final map = <String, dynamic>{};
      parsed.forEach((key, value) {
        map[key.toString()] = value;
      });

      // Case-insensitive key lookup.
      String? valueForKeys(List<String> keys) {
        for (final wanted in keys) {
          for (final entry in map.entries) {
            if (entry.key.toLowerCase() == wanted.toLowerCase()) {
              final text = entry.value?.toString().trim() ?? '';
              if (text.isNotEmpty) return text;
            }
          }
        }
        return null;
      }

      final rawId = valueForKeys(const [
        'invoiceid',
        'invoice_id',
        'invoiceId',
        'InvoiceID',
        'InvoiceId',
        'id',
      ]);
      if (rawId != null) {
        invoiceId = _extractUuid(rawId) ?? rawId;
      }

      final rawDiscount = valueForKeys(const ['discount', 'Discount']);
      if (rawDiscount != null) {
        discountPercent = double.tryParse(rawDiscount);
      }
    }

    // Fallback for plain UUID, JS-like `{invoiceid: ..., discount: 20}`, etc.
    if (invoiceId == null || discountPercent == null) {
      final text = body?.toString() ?? '';
      invoiceId ??= _extractInvoiceIdFromText(text);
      discountPercent ??= _extractDiscountFromText(text);
    }

    debugPrint(
      'InvoiceWebhookResult parsed invoiceId=$invoiceId discount=$discountPercent from body=$body',
    );

    return InvoiceWebhookResult(
      statusCode: statusCode,
      body: body,
      invoiceId: invoiceId,
      discountPercent: discountPercent,
    );
  }

  static String? _extractUuid(String text) {
    final match = _uuidPattern.firstMatch(text.trim());
    return match?.group(0);
  }

  static String? _extractInvoiceIdFromText(String text) {
    final named = _invoiceIdInText.firstMatch(text);
    if (named != null) return named.group(1);
    // Legacy response: body is only the UUID.
    final only = text.trim();
    if (_uuidPattern.hasMatch(only) && only.length <= 40) {
      return _extractUuid(only);
    }
    return _extractUuid(text);
  }

  static double? _extractDiscountFromText(String text) {
    final match = _discountInText.firstMatch(text);
    if (match == null) return null;
    return double.tryParse(match.group(1) ?? '');
  }
}
