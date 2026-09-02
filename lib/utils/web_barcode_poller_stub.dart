import 'dart:ui';

/// Stub for non-web platforms.
class WebBarcodePoller {
  bool get isRunning => false;

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
