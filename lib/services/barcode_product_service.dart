import 'package:flutter/foundation.dart';
import 'package:pwa/utils/barcode_normalize.dart';
import 'package:pwa/models/xero_product.dart';
import 'package:pwa/supabase/supabase_config.dart';

class BarcodeProductLookup {
  final bool ok;
  final String barcode;
  final String? material;
  final String? materialName;
  final XeroProduct? product;
  final String? error;
  final String message;

  const BarcodeProductLookup({
    required this.ok,
    required this.barcode,
    required this.material,
    required this.materialName,
    required this.product,
    required this.error,
    required this.message,
  });
}

class BarcodeProductService {
  static const String functionName = 'get_product_frombarcode';

  static Future<BarcodeProductLookup> lookup(String barcode) async {
    final normalized = BarcodeNormalize.primary(barcode) ?? barcode.trim();
    final code = normalized.trim();
    if (code.isEmpty) {
      return const BarcodeProductLookup(
        ok: false,
        barcode: '',
        material: null,
        materialName: null,
        product: null,
        error: 'invalid_barcode',
        message: 'No barcode to look up.',
      );
    }

    try {
      debugPrint(
        'BarcodeProductService: invoking $functionName at ${SupabaseConfig.edgeFunctionUrl(functionName)}',
      );
      final res = await SupabaseConfig.client.functions
          .invoke(
            functionName,
            body: {'barcode': code},
            headers: const {'content-type': 'application/json'},
          )
          .timeout(const Duration(seconds: 25));

      final data = res.data;
      if (data is! Map) {
        return BarcodeProductLookup(
          ok: false,
          barcode: code,
          material: null,
          materialName: null,
          product: null,
          error: 'bad_response',
          message: 'Unexpected response from product lookup.',
        );
      }

      final map = Map<String, dynamic>.from(data);
      final productRaw = map['product'];
      XeroProduct? product;
      if (productRaw is Map) {
        final parsed = XeroProduct.fromRow(Map<String, dynamic>.from(productRaw));
        if (parsed.xeroItemId.isNotEmpty && parsed.name.trim().isNotEmpty) {
          product = parsed;
        }
      }

      final ok = map['ok'] == true && product != null;
      final error = map['error']?.toString();
      final message = map['message']?.toString().trim();
      return BarcodeProductLookup(
        ok: ok,
        barcode: map['barcode']?.toString() ?? code,
        material: map['material']?.toString(),
        materialName: map['materialName']?.toString(),
        product: product,
        error: error,
        message: (message != null && message.isNotEmpty)
            ? message
            : (ok ? 'Product found.' : 'No product found for this barcode.'),
      );
    } catch (e) {
      debugPrint('BarcodeProductService.lookup failed: $e');
      final msg = e.toString().toLowerCase();
      final unreachable = msg.contains('failed to fetch') ||
          msg.contains('clientexception') ||
          msg.contains('clientfailed');
      return BarcodeProductLookup(
        ok: false,
        barcode: code,
        material: null,
        materialName: null,
        product: null,
        error: 'lookup_failed',
        message: unreachable
            ? 'Product lookup is unreachable. Deploy get_product_frombarcode and keep barcode Excel files in Storage bucket Barcode_Info.'
            : 'Could not look up this barcode. Please try again.',
      );
    }
  }
}
