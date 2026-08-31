import 'dart:ui';

import 'package:pwa/utils/web_scan_diagnostics.dart';

/// Stub for non-web platforms.
class WebBarcodePoller {
  bool get isRunning => false;

  Future<bool> get isSupported async => false;

  double? get focusScore => null;

  WebScanDiagnostics get diagnostics => const WebScanDiagnostics.unavailable();

  void setFocusSampleInPreview(Offset previewPoint) {}

  void setScanRegion({
    required Size previewSize,
    required Rect cropInPreview,
  }) {}

  void start({
    required void Function(String value) onCode,
    Size? previewSize,
    Rect? cropInPreview,
    Duration interval = const Duration(milliseconds: 120),
  }) {}

  void stop() {}
}

Future<String?> detectFromActiveVideo({
  Size previewSize = Size.zero,
  Rect cropInPreview = Rect.zero,
}) async =>
    null;
