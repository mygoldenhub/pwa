/// Normalize scanned barcodes for product lookup.
///
/// Handles GS1 labels like `(01)09315021121551(30)0020` and maps GTIN-14
/// (09315021121551) to EAN-13 (9315021121551) used in supplier spreadsheets.
class BarcodeNormalize {
  static String digitsOnly(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  /// All lookup keys for a raw scan value.
  static List<String> lookupKeys(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const [];

    final candidates = <String>{};

    // Human-readable GS1: (01)09315021121551(30)0020
    for (final m in RegExp(r'\(\s*01\s*\)\s*([0-9]{13,14})', caseSensitive: false).allMatches(text)) {
      final g = digitsOnly(m.group(1) ?? '');
      if (g.length >= 13) {
        candidates.add(g.length == 14 ? g : g.padLeft(14, '0'));
      }
    }

    final digits = digitsOnly(text);
    if (digits.isNotEmpty) {
      // Element string: AI 01 + fixed 14-digit GTIN.
      if (digits.startsWith('01') && digits.length >= 16) {
        candidates.add(digits.substring(2, 16));
      }
      candidates.add(digits);
    }

    final keys = <String>{};
    for (final c in candidates) {
      keys.addAll(_gtinVariants(c));
    }
    return keys.toList();
  }

  /// Preferred display / primary lookup value (GTIN-14 when available).
  static String? primary(String raw) {
    final keys = lookupKeys(raw);
    if (keys.isEmpty) return null;
    final gtin14 = keys.where((k) => k.length == 14).toList();
    if (gtin14.isNotEmpty) return gtin14.first;
    final gtin13 = keys.where((k) => k.length == 13).toList();
    if (gtin13.isNotEmpty) return gtin13.first;
    return keys.first;
  }

  static Iterable<String> _gtinVariants(String digits) sync* {
    final d = digitsOnly(digits);
    if (d.isEmpty) return;
    yield d;
    // GTIN-14 with leading 0 packaging digit -> EAN-13
    if (d.length == 14 && d.startsWith('0')) yield d.substring(1);
    // EAN-13 -> GTIN-14
    if (d.length == 13) yield '0$d';
    // UPC-A (12) -> EAN-13 / GTIN-14
    if (d.length == 12) yield '0$d';
  }
}
