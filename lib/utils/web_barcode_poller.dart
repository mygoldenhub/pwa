import 'dart:ui';

import 'web_barcode_poller_stub.dart'
    if (dart.library.html) 'web_barcode_poller_web.dart' as impl;

typedef WebBarcodePoller = impl.WebBarcodePoller;
