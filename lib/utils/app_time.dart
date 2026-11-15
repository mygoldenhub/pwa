/// Display helpers for timestamps.
///
/// Every timestamp in Supabase is stored in UTC (GMT). The app shows them in the
/// user's own timezone — the one set on their computer/phone (browser timezone on
/// web), including the correct daylight-saving offset for each date.
class AppTime {
  AppTime._();

  static final RegExp _explicitTz = RegExp(r'(Z|[+-]\d{2}(:?\d{2})?)$', caseSensitive: false);
  static final RegExp _xeroLegacy = RegExp(r'/Date\((-?\d+)');

  /// Parses a value from Supabase/Xero as a UTC instant.
  ///
  /// Strings without an explicit offset (e.g. `2024-01-01T12:34:56` or
  /// `2024-01-01`) are treated as UTC, because that is how Supabase stores them.
  /// Xero's legacy `/Date(1700000000000+0000)/` format is supported too.
  static DateTime? parseUtc(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return null;

    final legacy = _xeroLegacy.firstMatch(text);
    if (legacy != null) return DateTime.fromMillisecondsSinceEpoch(int.parse(legacy[1]!), isUtc: true);

    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    if (parsed.isUtc || _explicitTz.hasMatch(text)) return parsed.toUtc();
    // No offset in the string: the wall-clock values are UTC.
    return DateTime.utc(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.minute, parsed.second,
        parsed.millisecond, parsed.microsecond);
  }

  /// Converts to the user's local (device) timezone.
  static DateTime? toLocal(dynamic value) => parseUtc(value)?.toLocal();

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// `yyyy-MM-dd` in the user's timezone.
  static String formatDate(dynamic value, {String empty = '—'}) {
    final d = toLocal(value);
    if (d == null) return empty;
    return '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';
  }

  /// `dd/MM/yyyy` in the user's timezone.
  static String formatDateDmy(dynamic value, {String empty = '—'}) {
    final d = toLocal(value);
    if (d == null) return empty;
    return '${_two(d.day)}/${_two(d.month)}/${d.year.toString().padLeft(4, '0')}';
  }

  /// `yyyy-MM-dd HH:mm` in the user's timezone.
  static String formatDateTime(dynamic value, {String empty = '—'}) {
    final d = toLocal(value);
    if (d == null) return empty;
    return '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';
  }
}
