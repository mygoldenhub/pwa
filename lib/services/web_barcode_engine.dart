/// Bridge to the PWA barcode engine in `web/scanner/ts_scanner.js`
/// (browser BarcodeDetector + self-hosted zxing-wasm).
///
/// Web only. Native Android/iOS builds use Huawei Scan Kit and get the no-op stub.
library;

export 'web_barcode_engine_stub.dart' if (dart.library.js_interop) 'web_barcode_engine_web.dart';
