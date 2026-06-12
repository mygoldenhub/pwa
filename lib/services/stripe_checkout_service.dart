import 'package:flutter/foundation.dart';
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
}
