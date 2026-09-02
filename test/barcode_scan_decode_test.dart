import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pwa/utils/barcode_scan_decode.dart';
import 'package:pwa/utils/barcode_validator.dart';

void main() {
  group('BarcodeValidator GS1-128', () {
    test('accepts human-readable (01) GTIN example', () {
      expect(
        BarcodeValidator.normalize('(01)09315021121728(30)0012'),
        '9315021121728',
      );
    });

    test('accepts element string with literal FNC1 markers', () {
      expect(
        BarcodeValidator.normalize('0109315021121728[FNC1]300012'),
        '9315021121728',
      );
    });

    test('looksLikeGs1 detects human-readable and element strings', () {
      expect(BarcodeValidator.looksLikeGs1('(01)09315021121728(30)0012'), isTrue);
      expect(BarcodeValidator.looksLikeGs1('0109315021121728300012'), isTrue);
      expect(BarcodeValidator.looksLikeGs1('9780201379624'), isFalse);
    });
  });

  group('BarcodeScanDecode', () {
    test('lists displayValue before rawValue', () {
      const barcode = Barcode(
        displayValue: '(01)09315021121728(30)0012',
        rawValue: '0109315021121728300012',
        format: BarcodeFormat.code128,
      );
      final candidates = BarcodeScanDecode.candidates(barcode);
      expect(candidates.first, '(01)09315021121728(30)0012');
      expect(candidates, contains('0109315021121728300012'));
    });

    test('normalizes any candidate from a GS1 barcode', () {
      const barcode = Barcode(
        displayValue: '(01)09315021121728(30)0012',
        format: BarcodeFormat.code128,
      );
      final normalized = BarcodeScanDecode.candidates(barcode)
          .map(BarcodeValidator.normalize)
          .whereType<String>()
          .toList();
      expect(normalized, contains('9315021121728'));
    });
  });
}
