import 'dart:convert';
import 'dart:typed_data';

import 'package:mobile_scanner/mobile_scanner.dart';

/// Collect every string form a scanner may emit for one barcode (GS1-128
/// often differs between [Barcode.displayValue], [Barcode.rawValue], and bytes).
class BarcodeScanDecode {
  const BarcodeScanDecode._();

  /// Unique, non-empty candidates in priority order (human-readable GS1 first).
  static List<String> candidates(Barcode barcode) {
    final seen = <String>{};
    final out = <String>[];

    void add(String? value) {
      if (value == null) return;
      final trimmed = value.trim();
      if (trimmed.isEmpty || seen.contains(trimmed)) return;
      seen.add(trimmed);
      out.add(trimmed);
    }

    // GS1-128 human-readable labels usually land in displayValue, while rawValue
    // can be Latin-1 element data or empty on some platforms.
    add(barcode.displayValue);
    add(barcode.rawValue);

    for (final derived in _fromBytes(barcode)) {
      add(derived);
    }

    return out;
  }

  static Iterable<String> _fromBytes(Barcode barcode) sync* {
    final decoded = barcode.rawDecodedBytes;
    if (decoded == null) {
      yield* _fromLegacyBytes(barcode.rawBytes);
      return;
    }

    switch (decoded) {
      case DecodedBarcodeBytes(:final bytes):
        yield* _stringsFromPayload(bytes);
      case DecodedVisionBarcodeBytes(:final bytes, :final rawBytes):
        if (bytes != null) {
          yield* _stringsFromPayload(bytes);
        }
        yield* _stringsFromPayload(rawBytes);
    }
  }

  static Iterable<String> _fromLegacyBytes(Uint8List? bytes) sync* {
    if (bytes == null || bytes.isEmpty) return;
    yield* _stringsFromPayload(bytes);
  }

  static Iterable<String> _stringsFromPayload(Uint8List bytes) sync* {
    if (bytes.isEmpty) return;

    // Printable Latin-1 (iOS Vision / Code128 GS1 element strings).
    final latin1 = _latin1Printable(bytes);
    if (latin1.isNotEmpty) yield latin1;

    // UTF-8 when the payload is valid text.
    try {
      final decodedUtf8 = utf8.decode(bytes, allowMalformed: true).trim();
      if (decodedUtf8.isNotEmpty && decodedUtf8 != latin1) yield decodedUtf8;
    } catch (_) {}

    // AIM ]C1 / ]e0 prefix + element string without non-printables.
    final compact = _compactGs1Element(bytes);
    if (compact.isNotEmpty && compact != latin1) yield compact;
  }

  static String _latin1Printable(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      if (byte == 0x1D) {
        buffer.write('\u001D');
        continue;
      }
      if (byte >= 32 && byte <= 126) {
        buffer.writeCharCode(byte);
      }
    }
    return buffer.toString().trim();
  }

  /// Builds `]C1` + element digits for payloads that omit the AIM prefix.
  static String _compactGs1Element(Uint8List bytes) {
    final digits = StringBuffer();
    var sawAi01 = false;
    for (final byte in bytes) {
      if (byte == 0x1D) continue;
      if (byte >= 48 && byte <= 57) {
        digits.writeCharCode(byte);
        continue;
      }
      if (byte == 0x5D && digits.isEmpty) {
        // ']' — likely start of AIM prefix; keep scanning.
        continue;
      }
    }
    final d = digits.toString();
    if (d.startsWith('01') && d.length >= 16) {
      sawAi01 = true;
    }
    if (!sawAi01) return '';
    return d;
  }
}
