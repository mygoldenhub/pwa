/// Validates and normalizes retail product barcodes (EAN-8, UPC-A, EAN-13)
/// and GS1-128 payloads that carry a GTIN in AI 01.
///
/// Pure string logic — no Flutter or scanner dependency — so it can be unit
/// tested without a camera.
class BarcodeValidator {
  const BarcodeValidator._();

  static final RegExp _digitsOnly = RegExp(r'^\d+$');
  static final RegExp _humanAi01 = RegExp(
    r'\(\s*01\s*\)\s*([0-9]{13,14})',
    caseSensitive: false,
  );
  /// AIM symbology identifier, e.g. ]C1 (Code 128) or ]e0 (GS1).
  static final RegExp _aimPrefix = RegExp(r'^\][A-Za-z][0-9]');
  static final RegExp _nonDigits = RegExp(r'\D');
  static final RegExp _gs1HumanAi01 = RegExp(
    r'\(\s*01\s*\)\s*\d',
    caseSensitive: false,
  );
  static final RegExp _fnc1Text = RegExp(r'\[FNC1\]', caseSensitive: false);
  static final RegExp _gsText = RegExp(r'(\{GS\}|<GS>)', caseSensitive: false);
  /// Control chars / Scan Kit FNC1 stand-ins often prefix GS1 element strings.
  static final RegExp _leadingNoise = RegExp(
    r'^[\x00-\x1F\x7F\u00E8\u00F1\u00F2\u00F3\u00F4]+',
  );

  /// True when [raw] looks like a GS1-128 label carrying GTIN AI 01.
  static bool looksLikeGs1(String raw) {
    final text = _preprocessGs1(raw.trim());
    if (text.isEmpty) return false;
    if (_gs1HumanAi01.hasMatch(text)) return true;
    if (_aimPrefix.hasMatch(text)) return true;
    final digits = text.replaceAll(_nonDigits, '');
    return digits.startsWith('01') && digits.length >= 16;
  }

  static String _preprocessGs1(String text) {
    return text
        .replaceAll(_fnc1Text, '\u001D')
        .replaceAll(_gsText, '\u001D')
        .replaceAll(_leadingNoise, '');
  }

  /// Every distinct string form to try for one scanner emission.
  ///
  /// Huawei Scan Kit may return human-readable GS1, an element string, AIM
  /// prefixes, and/or embedded Group Separator (FNC1) bytes.
  static List<String> scanCandidates(String raw) {
    final seen = <String>{};
    final out = <String>[];

    void add(String? value) {
      if (value == null) return;
      final trimmed = value.trim();
      if (trimmed.isEmpty || seen.contains(trimmed)) return;
      seen.add(trimmed);
      out.add(trimmed);
    }

    final text = raw.trim();
    add(text);
    add(_preprocessGs1(text));

    var stripped = text.replaceAll('\u001D', '');
    stripped = stripped.replaceFirst(_aimPrefix, '');
    stripped = stripped.replaceAll(_leadingNoise, '');
    add(stripped);
    add(_preprocessGs1(stripped));

    // Digit compaction only for GS1-shaped payloads — not for "EAN + junk"
    // like 9780201379624X, which must stay rejected.
    if (looksLikeGs1(text) || _aimPrefix.hasMatch(text)) {
      final digits = text.replaceAll(_nonDigits, '');
      add(digits);
      if (digits.startsWith('01') && digits.length >= 16) {
        add(digits.substring(2, 16));
      }
    }

    for (final m in _humanAi01.allMatches(text)) {
      final g = m.group(1);
      if (g == null) continue;
      add(g);
      add(g.length == 13 ? '0$g' : g);
      add('(01)$g');
    }

    return out;
  }

  /// Returns a normalized barcode, or `null` if [raw] is not a valid product
  /// code.
  ///
  /// Rules:
  /// - Digit-only values of length 8, 12, or 13 (EAN-8 / UPC-A / EAN-13).
  /// - GS1-128: extract the 14-digit GTIN from AI 01, e.g.
  ///   `(01)09315021121728(30)0012` or `0109315021121728300012`.
  /// - Mod-10 (GS1) check digit must be valid.
  /// - UPC-A (12 digits) is converted to EAN-13 by prefixing `"0"`.
  /// - GTIN-14 with a leading `0` packaging indicator becomes EAN-13.
  ///
  /// UPC-E is also 8 digits and cannot be distinguished from EAN-8 from the
  /// digits alone, so 8-digit values are left as-is after check-digit
  /// validation rather than expanded to UPC-A / EAN-13.
  static String? normalize(String raw) {
    for (final candidate in scanCandidates(raw)) {
      final normalized = _normalizeOne(candidate);
      if (normalized != null) return normalized;
    }
    return null;
  }

  static String? _normalizeOne(String raw) {
    final text = _preprocessGs1(raw.trim());
    if (text.isEmpty) return null;

    final retail = _normalizeRetail(text);
    if (retail != null) return retail;

    final gtin14 = _extractGtin14(text);
    if (gtin14 == null) return null;
    return _normalizeGtin14(gtin14);
  }

  /// True when [raw] is an accepted product barcode.
  static bool isValid(String raw) => normalize(raw) != null;

  static String? _normalizeRetail(String digits) {
    if (!_digitsOnly.hasMatch(digits)) return null;

    switch (digits.length) {
      case 8:
        if (!_hasValidCheckDigit(digits)) return null;
        return digits;
      case 12:
        if (!_hasValidCheckDigit(digits)) return null;
        return '0$digits';
      case 13:
        if (!_hasValidCheckDigit(digits)) return null;
        return digits;
      default:
        return null;
    }
  }

  static String? _normalizeGtin14(String gtin14) {
    if (gtin14.length != 14 || !_digitsOnly.hasMatch(gtin14)) return null;
    if (!_hasValidCheckDigit(gtin14)) return null;
    if (gtin14.startsWith('0')) {
      final ean13 = gtin14.substring(1);
      if (!_hasValidCheckDigit(ean13)) return null;
      return ean13;
    }
    return gtin14;
  }

  /// GTIN-14 from a GS1-128 / GS1 element string, or a bare 14-digit GTIN.
  static String? _extractGtin14(String raw) {
    var stripped = raw.replaceAll('\u001D', '');
    // Strip every leading AIM prefix (rare double-prefix devices).
    while (_aimPrefix.hasMatch(stripped)) {
      stripped = stripped.replaceFirst(_aimPrefix, '');
    }
    stripped = stripped.replaceAll(_leadingNoise, '');

    final human = _humanAi01.firstMatch(stripped);
    if (human != null) {
      var gtin = human.group(1)!;
      if (gtin.length == 13) gtin = '0$gtin';
      return gtin;
    }

    final digits = stripped.replaceAll(_nonDigits, '');
    if (digits.startsWith('01') && digits.length >= 16) {
      return digits.substring(2, 16);
    }
    // Some scanners omit AI "01" and return the 14-digit GTIN alone.
    if (digits.length == 14) return digits;
    // Or the retail EAN-13 inside a longer noisy payload.
    if (digits.length > 14 && digits.startsWith('0')) {
      final gtin14 = digits.substring(0, 14);
      if (_hasValidCheckDigit(gtin14)) return gtin14;
    }
    return null;
  }

  /// GS1 mod-10 check digit. Weights alternate 3, 1, 3, … from the right
  /// (the check digit itself is the rightmost digit).
  static bool _hasValidCheckDigit(String digits) {
    if (digits.length < 2) return false;
    final expected = checkDigitFor(digits.substring(0, digits.length - 1));
    if (expected == null) return false;
    return expected == int.parse(digits[digits.length - 1]);
  }

  /// Check digit for the given payload (digits without the check digit).
  ///
  /// Exposed for tests.
  static int? checkDigitFor(String payload) {
    if (payload.isEmpty || !_digitsOnly.hasMatch(payload)) return null;
    var sum = 0;
    for (var i = 0; i < payload.length; i++) {
      final digit = payload.codeUnitAt(i) - 48;
      // Rightmost payload digit is one left of the check digit, so it has
      // weight 3 (odd position from the right of the full number).
      final fromRight = payload.length - 1 - i;
      final weight = fromRight.isEven ? 3 : 1;
      sum += digit * weight;
    }
    return (10 - (sum % 10)) % 10;
  }
}
