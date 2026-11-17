import 'dart:async';
import 'dart:js_interop';

@JS('tsScanner')
external _TsScanner? get _tsScanner;

extension type _TsScanner._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> startLive(JSObject video, JSFunction onCodes, JSFunction onError);
  external void stop();
  external bool torchSupported();
  external JSPromise<JSBoolean> setTorch(bool on);
  external JSPromise<JSArray<JSString>?> decodePhoto();
}

/// Web implementation backed by `window.tsScanner` (web/scanner/ts_scanner.js).
class WebBarcodeEngine {
  const WebBarcodeEngine._();

  /// The engine is an ES module loaded by index.html; wait briefly for it to register.
  static Future<bool> waitUntilReady({Duration timeout = const Duration(seconds: 8)}) async {
    final deadline = DateTime.now().add(timeout);
    while (_tsScanner == null) {
      if (DateTime.now().isAfter(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return true;
  }

  /// Starts the rear camera in [videoElement] (a `<video>` from `HtmlElementView`) and
  /// reports decoded raw values. Error codes: `permission`, `no-camera`, `busy`, `insecure`,
  /// `engine`, `error:<message>`.
  static Future<void> startLive(
    Object videoElement, {
    required void Function(List<String> rawValues) onCodes,
    required void Function(String errorCode) onError,
  }) async {
    final engine = _tsScanner;
    if (engine == null) {
      onError('engine');
      return;
    }
    await engine
        .startLive(
          videoElement as JSObject,
          ((JSArray<JSString> codes) {
            onCodes([for (final c in codes.toDart) c.toDart]);
          }).toJS,
          ((JSString code) {
            onError(code.toDart);
          }).toJS,
        )
        .toDart;
  }

  static void stop() => _tsScanner?.stop();

  static bool torchSupported() => _tsScanner?.torchSupported() ?? false;

  static Future<bool> setTorch(bool on) async {
    final engine = _tsScanner;
    if (engine == null) return false;
    return (await engine.setTorch(on).toDart).toDart;
  }

  /// Opens the phone's camera app and decodes the photo. Call directly from a tap handler.
  /// Returns raw values (`[]` when none were found) or `null` when cancelled.
  static Future<List<String>?> decodePhoto() async {
    final engine = _tsScanner;
    if (engine == null) return null;
    final result = await engine.decodePhoto().toDart;
    if (result == null) return null;
    return [for (final c in result.toDart) c.toDart];
  }
}
