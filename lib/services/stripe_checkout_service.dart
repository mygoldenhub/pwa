import 'package:flutter/foundation.dart';
import 'package:pwa/supabase/supabase_config.dart';

class StripeCheckoutService {
  static const String _fn = 'create_stripe_checkout_session';

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
}
