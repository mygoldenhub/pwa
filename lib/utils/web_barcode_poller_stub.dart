import 'dart:ui';

/// Stub for non-web platforms.
class WebBarcodePoller {
  bool get isRunning => false;

  Future<bool> get isSupported async => false;

  void setScanRegion({
    required Size previewSize,
    required Rect cropInPreview,
    double previewZoom = 1.0,
  }) {}

  void start({
    required void Function(String value) onCode,
    Size? previewSize,
    Rect? cropInPreview,
    double previewZoom = 1.0,
    Duration interval = const Duration(milliseconds: 150),
  }) {}

  void stop() {}
}

Future<String?> detectFromActiveVideo({
  Size previewSize = Size.zero,
  Rect cropInPreview = Rect.zero,
  double previewZoom = 1.0,
}) async =>
    null;
