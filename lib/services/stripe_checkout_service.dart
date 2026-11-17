import 'package:flutter/foundation.dart';
import 'package:pwa/models/cart_item.dart';
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

  /// Stripe line items for a cart, with the customer's Xero discount applied the way Xero does it
  /// (Tax Exclusive invoices):
  /// - each line = unit price × quantity × (1 − discount%), rounded to cents
  /// - GST = 10% of each discounted line, rounded per line, added as one "GST (10%)" line.
  ///
  /// e.g. 48.07 with 15% off → 40.86, GST 4.09, total 44.95.
  /// Each line is sent as quantity 1 with the full line amount so Stripe's total matches Xero exactly.
  static List<({String name, int unitAmountCents, int quantity})> buildDiscountedCartLineItems({
    required List<CartItem> cartItems,
    double? discountPercent,
    double gstRate = 0.10,
  }) {
    final discount = (discountPercent == null || discountPercent <= 0 || discountPercent >= 100) ? 0.0 : discountPercent;
    final multiplier = 1 - discount / 100;
    final discountLabel = discount == 0
        ? ''
        : ' (${discount == discount.roundToDouble() ? discount.toInt() : discount}% discount)';

    final items = <({String name, int unitAmountCents, int quantity})>[];
    var gstCents = 0;
    for (final c in cartItems) {
      final name = c.productName.trim();
      final unitCents = c.unitPriceCents ?? 0;
      if (name.isEmpty || unitCents <= 0 || c.quantity <= 0) continue;
      final lineCents = (unitCents * c.quantity * multiplier).round();
      if (lineCents <= 0) continue;
      gstCents += (lineCents * gstRate).round();
      final title = c.quantity > 1 ? '$name × ${c.quantity}' : name;
      items.add((name: '$title$discountLabel', unitAmountCents: lineCents, quantity: 1));
    }
    if (gstCents > 0) {
      items.add((name: 'GST (${(gstRate * 100).round()}%)', unitAmountCents: gstCents, quantity: 1));
    }
    return items;
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

      // Xero's LineAmount is after the customer's discount; UnitAmount is the list price.
      // Charge the line amount (as one line) so discounted invoices aren't overcharged.
      if (totalRaw != null && totalRaw > 0) {
        final cents = (totalRaw * 100).round();
        items.add((name: qty > 1 ? '$title × $qty' : title, unitAmountCents: cents, quantity: 1));
        continue;
      }

      final unitAmount = (unitRaw ?? 0).toDouble();
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
