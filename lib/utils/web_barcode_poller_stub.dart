import 'dart:ui';

/// Stub for non-web platforms.
class WebBarcodePoller {
  bool get isRunning => false;

  void setScanRegion({
    required Size previewSize,
    required Rect cropInPreview,
    double decodeMagnify = 1.0,
  }) {}

  void start({
    required void Function(String value) onCode,
    Size? previewSize,
    Rect? cropInPreview,
    double decodeMagnify = 1.0,
    Duration interval = const Duration(milliseconds: 80),
  }) {}

  void updateRegion({
    required Size previewSize,
    required Rect cropInPreview,
    double decodeMagnify = 1.0,
  }) {}

  void stop() {}
}
