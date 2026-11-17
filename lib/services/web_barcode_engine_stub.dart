/// No-op engine for native builds (they use Huawei Scan Kit).
class WebBarcodeEngine {
  const WebBarcodeEngine._();

  static Future<bool> waitUntilReady() async => false;

  static Future<void> startLive(
    Object videoElement, {
    required void Function(List<String> rawValues) onCodes,
    required void Function(String errorCode) onError,
  }) async =>
      onError('unsupported');

  static void stop() {}

  static bool torchSupported() => false;

  static Future<bool> setTorch(bool on) async => false;

  static Future<List<String>?> decodePhoto() async => null;
}
