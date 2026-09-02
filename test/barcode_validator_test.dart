import 'package:flutter_test/flutter_test.dart';
import 'package:pwa/utils/barcode_validator.dart';

void main() {
  group('BarcodeValidator.normalize', () {
    test('accepts a valid EAN-13', () {
      expect(BarcodeValidator.normalize('9780201379624'), '9780201379624');
    });

    test('accepts a valid EAN-8', () {
      expect(BarcodeValidator.normalize('90311017'), '90311017');
    });

    test('converts valid UPC-A (12 digits) to EAN-13', () {
      expect(BarcodeValidator.normalize('036000291452'), '0036000291452');
    });

    test('rejects an EAN-13 with a bad check digit', () {
      expect(BarcodeValidator.normalize('9780201379625'), isNull);
    });

    test('rejects a UPC-A with a bad check digit', () {
      expect(BarcodeValidator.normalize('036000291453'), isNull);
    });

    test('rejects an EAN-8 with a bad check digit', () {
      expect(BarcodeValidator.normalize('90311018'), isNull);
    });

    test('rejects non-digit values', () {
      expect(BarcodeValidator.normalize('ABC123456789'), isNull);
      expect(BarcodeValidator.normalize('9780201379624X'), isNull);
    });

    test('rejects lengths other than 8, 12, or 13', () {
      expect(BarcodeValidator.normalize('1234567'), isNull);
      expect(BarcodeValidator.normalize('12345678901'), isNull);
      expect(BarcodeValidator.normalize('12345678901234'), isNull);
      expect(BarcodeValidator.normalize(''), isNull);
    });

    test('trims whitespace before validating', () {
      expect(BarcodeValidator.normalize(' 9780201379624 '), '9780201379624');
    });

    test('extracts GTIN from GS1-128 human-readable AI 01', () {
      expect(
        BarcodeValidator.normalize('(01)09315021121728(30)0012'),
        '9315021121728',
      );
    });

    test('extracts GTIN from a GS1-128 element string', () {
      expect(
        BarcodeValidator.normalize('0109315021121728300012'),
        '9315021121728',
      );
    });

    test('extracts GTIN when FNC1 / GS separators are present', () {
      expect(
        BarcodeValidator.normalize('0109315021121728\u001D300012'),
        '9315021121728',
      );
    });

    test('strips an AIM ]C1 prefix from GS1-128', () {
      expect(
        BarcodeValidator.normalize(']C10109315021121728300012'),
        '9315021121728',
      );
    });

    test('rejects GS1-128 with a bad GTIN check digit', () {
      expect(
        BarcodeValidator.normalize('(01)09315021121729(30)0012'),
        isNull,
      );
    });

    test('rejects non-GS1 Code 128 text', () {
      expect(BarcodeValidator.normalize('HELLO123'), isNull);
    });
  });

  group('BarcodeValidator.checkDigitFor', () {
    test('matches known EAN-13 / UPC-A / EAN-8 check digits', () {
      expect(BarcodeValidator.checkDigitFor('978020137962'), 4);
      expect(BarcodeValidator.checkDigitFor('03600029145'), 2);
      expect(BarcodeValidator.checkDigitFor('9031101'), 7);
    });
  });
}
