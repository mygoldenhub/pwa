import 'package:flutter/material.dart';
import 'package:pwa/pages/xero_product_detail_page.dart';

/// After a barcode is recognized, open product info and look it up immediately.
class BarcodeResultPage extends StatelessWidget {
  final String barcode;

  const BarcodeResultPage({super.key, required this.barcode});

  @override
  Widget build(BuildContext context) {
    return XeroProductDetailPage(barcode: barcode);
  }
}
