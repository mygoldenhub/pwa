import 'package:flutter/foundation.dart';
import 'package:pwa/models/xero_invoice.dart';
import 'package:pwa/supabase/supabase_config.dart';

class StripeCheckoutService {
  static const String _fn = 'create_stripe_checkout_session';
  static const String _receiptFn = 'get_stripe_checkout_receipt';

  static ({Uri? receiptUrl, Uri? hostedInvoiceUrl}) _parseReceiptResponse(dynamic data) {
    if (data is! Map) return (receiptUrl: null, hostedInvoiceUrl: null);
    final receipt = data['receiptUrl']?.toString();
    final invoice = data['hostedInvoiceUrl']?.toString();
    return (
      receiptUrl: (receipt != null && receipt.trim().isNotEmpty) ? Uri.tryParse(receipt.trim()) : null,
      hostedInvoiceUrl: (invoice != null && invoice.trim().isNotEmpty) ? Uri.tryParse(invoice.trim()) : null,
    );
  }

  /// Creates a Stripe hosted checkout session and returns its URL.
  static Future<Uri> createHostedCheckoutUrl({
    required String currency,
    required String reference,
    String? invoiceId,
    required List<({String name, int unitAmountCents, int quantity})> lineItems,
    String? successUrl,
    String? cancelUrl,
    String? customerEmail,
  }) async {
    try {
      final body = {
        'currency': currency,
        'reference': reference,
        'invoiceId': invoiceId,
        'successUrl': successUrl,
        'cancelUrl': cancelUrl,
        'customerEmail': customerEmail,
        'lineItems': lineItems
            .where((e) => e.name.trim().isNotEmpty && e.unitAmountCents > 0 && e.quantity > 0)
            .map((e) => {
                  'name': e.name.trim(),
                  'unitAmountCents': e.unitAmountCents,
                  'quantity': e.quantity,
                })
            .toList(),
      };

      final res = await SupabaseConfig.client.functions.invoke(_fn, body: body);
      final data = res.data;
      if (data is! Map) throw 'Stripe checkout response is not an object.';
      final url = data['url']?.toString();
      if (url == null || url.trim().isEmpty) throw 'Stripe checkout URL missing.';
      return Uri.parse(url);
    } catch (e) {
      debugPrint('StripeCheckoutService.createHostedCheckoutUrl failed: $e');
      rethrow;
    }
  }

  /// After Stripe redirects back to the app (success_url), fetch the receipt/invoice URL.
  ///
  /// - [hostedInvoiceUrl] is present only if Stripe invoice creation is enabled.
  /// - [receiptUrl] is usually present for standard one-off payments.
  static Future<({Uri? receiptUrl, Uri? hostedInvoiceUrl})> getReceiptUrls({required String sessionId}) async {
    try {
      final res = await SupabaseConfig.client.functions.invoke(_receiptFn, body: {'sessionId': sessionId});
      return _parseReceiptResponse(res.data);
    } catch (e) {
      debugPrint('StripeCheckoutService.getReceiptUrls failed: $e');
      rethrow;
    }
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static String _lineItemTitle(Map<String, dynamic> li) {
    final v = (li['description'] ??
            li['Description'] ??
            li['name'] ??
            li['ItemCode'] ??
            li['item_code'] ??
            li['reference'])
        ?.toString()
        .trim();
    return (v == null || v.isEmpty) ? 'Line item' : v;
  }

  /// Builds Stripe Checkout line items from a Xero invoice.
  ///
  /// Stripe quantities must be integers; fractional quantities are rounded.
  /// If line items are missing or invalid, falls back to a single line item
  /// based on invoice [amountDue] / [total].
  static List<({String name, int unitAmountCents, int quantity})> buildLineItemsFromInvoice(XeroInvoice invoice) {
    final currency = (invoice.currencyCode ?? '').trim();
    final fallbackAmount = (invoice.amountDue ?? invoice.total ?? 0).toDouble();

    final items = <({String name, int unitAmountCents, int quantity})>[];
    for (final li in invoice.lineItems) {
      final title = _lineItemTitle(li);
      final qtyRaw = _asDouble(li['quantity'] ?? li['Quantity']);
      final unitRaw = _asDouble(li['unit_amount'] ?? li['UnitAmount'] ?? li['unitAmount']);
      final totalRaw = _asDouble(li['line_amount'] ?? li['LineAmount'] ?? li['lineAmount']);

      final qty = (qtyRaw == null || qtyRaw <= 0) ? 1 : qtyRaw.round();
      double unitAmount = (unitRaw ?? 0).toDouble();
      if (unitAmount <= 0 && totalRaw != null && qty > 0) unitAmount = totalRaw / qty;

      final cents = (unitAmount * 100).round();
      if (cents <= 0) continue;
      items.add((name: title, unitAmountCents: cents, quantity: qty));
    }

    if (items.isNotEmpty) {
      // Xero line items often store tax separately (`TaxAmount`).
      // To ensure Stripe collects the full amount due, add a dedicated tax line.
      final tax = (invoice.totalTax ?? 0).toDouble();
      final taxCents = (tax * 100).round();
      if (taxCents > 0) {
        return [...items, (name: 'Tax', unitAmountCents: taxCents, quantity: 1)];
      }
      return items;
    }

    final cents = (fallbackAmount * 100).round();
    final invNum = (invoice.invoiceNum ?? '').trim();
    final name = invNum.isEmpty ? 'Invoice ($currency)' : 'Invoice $invNum';
    return [(name: name, unitAmountCents: cents <= 0 ? 1 : cents, quantity: 1)];
  }
}
