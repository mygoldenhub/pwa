import 'dart:ui';

import 'web_barcode_poller_stub.dart'
    if (dart.library.html) 'web_barcode_poller_web.dart' as impl;

typedef WebBarcodePoller = impl.WebBarcodePoller;

Future<String?> detectFromActiveVideo({
  Size previewSize = Size.zero,
  Rect cropInPreview = Rect.zero,
  double previewZoom = 1.0,
}) =>
    impl.detectFromActiveVideo(
      previewSize: previewSize,
      cropInPreview: cropInPreview,
      previewZoom: previewZoom,
    );
