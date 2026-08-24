import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Extra live barcode polling for web, using the browser BarcodeDetector API.
class WebBarcodePoller {
  Timer? _timer;
  bool _busy = false;
  void Function(String value)? _onCode;
  Size _previewSize = Size.zero;
  Rect _cropInPreview = Rect.zero;

  bool get isRunning => _timer != null;

  Future<bool> get isSupported async {
    final detector = globalContext.getProperty('BarcodeDetector'.toJS);
    return detector != null;
  }

  void setScanRegion({
    required Size previewSize,
    required Rect cropInPreview,
  }) {
    _previewSize = previewSize;
    _cropInPreview = cropInPreview;
  }

  void start({
    required void Function(String value) onCode,
    Size? previewSize,
    Rect? cropInPreview,
    Duration interval = const Duration(milliseconds: 150),
  }) {
    stop();
    _onCode = onCode;
    if (previewSize != null) _previewSize = previewSize;
    if (cropInPreview != null) _cropInPreview = cropInPreview;
    _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _onCode = null;
    _busy = false;
  }

  Future<void> _tick() async {
    if (_busy) return;
    _busy = true;
    try {
      final code = await detectFromActiveVideo(
        previewSize: _previewSize,
        cropInPreview: _cropInPreview,
      );
      if (code != null && code.isNotEmpty) {
        _onCode?.call(code);
      }
    } catch (e) {
      debugPrint('WebBarcodePoller tick failed: $e');
    } finally {
      _busy = false;
    }
  }
}

JSObject? _firstLiveVideo() {
  final document = globalContext.getProperty('document'.toJS) as JSObject;
  final videos = document.callMethod('querySelectorAll'.toJS, 'video'.toJS);
  if (videos == null) return null;
  final list = videos as JSObject;
  final lengthValue = list.getProperty('length'.toJS)?.dartify();
  final length = lengthValue is num ? lengthValue.toInt() : 0;
  for (var i = 0; i < length; i++) {
    final video = list.callMethod('item'.toJS, i.toJS);
    if (video == null) continue;
    final jsVideo = video as JSObject;
    final ready = jsVideo.getProperty('readyState'.toJS)?.dartify();
    if (ready is num && ready >= 2) return jsVideo;
  }
  return null;
}

JSObject? _makeDetector(JSAny detectorCtor) {
  final options = JSObject();
  options.setProperty(
    'formats'.toJS,
    <JSAny>[
      'ean_13'.toJS,
      'ean_8'.toJS,
      'upc_a'.toJS,
      'upc_e'.toJS,
      'code_128'.toJS,
      'code_39'.toJS,
      'codabar'.toJS,
      'itf'.toJS,
      'qr_code'.toJS,
    ].toJS,
  );
  try {
    return (detectorCtor as JSFunction).callAsConstructor(options) as JSObject;
  } catch (_) {
    try {
      return (detectorCtor as JSFunction).callAsConstructor() as JSObject;
    } catch (e) {
      debugPrint('BarcodeDetector constructor failed: $e');
      return null;
    }
  }
}

/// Map a preview-space rect onto video pixels using BoxFit.cover.
Rect _previewRectToVideo(Rect crop, Size preview, double videoW, double videoH) {
  if (preview.width <= 0 || preview.height <= 0) {
    return Rect.fromLTWH(0, 0, videoW, videoH);
  }
  final scaleX = preview.width / videoW;
  final scaleY = preview.height / videoH;
  final scale = scaleX > scaleY ? scaleX : scaleY;
  final dx = (preview.width - videoW * scale) / 2;
  final dy = (preview.height - videoH * scale) / 2;

  final left = ((crop.left - dx) / scale).clamp(0.0, videoW);
  final top = ((crop.top - dy) / scale).clamp(0.0, videoH);
  final right = ((crop.right - dx) / scale).clamp(0.0, videoW);
  final bottom = ((crop.bottom - dy) / scale).clamp(0.0, videoH);
  return Rect.fromLTRB(left, top, right, bottom);
}

JSObject? _cropVideoToCanvas(JSObject video, double videoW, double videoH, Rect videoCrop) {
  try {
    final document = globalContext.getProperty('document'.toJS) as JSObject;
    final canvas = document.callMethod('createElement'.toJS, 'canvas'.toJS);
    if (canvas == null) return null;
    final jsCanvas = canvas as JSObject;

    final sx = videoCrop.left.clamp(0.0, videoW - 1);
    final sy = videoCrop.top.clamp(0.0, videoH - 1);
    final sw = videoCrop.width.clamp(8.0, videoW - sx);
    final sh = videoCrop.height.clamp(8.0, videoH - sy);

    jsCanvas.setProperty('width'.toJS, sw.round().toJS);
    jsCanvas.setProperty('height'.toJS, sh.round().toJS);

    final ctx = jsCanvas.callMethod('getContext'.toJS, '2d'.toJS);
    if (ctx == null) return null;
    (ctx as JSObject).callMethodVarArgs(
      'drawImage'.toJS,
      [
        video,
        sx.toJS,
        sy.toJS,
        sw.toJS,
        sh.toJS,
        0.toJS,
        0.toJS,
        sw.toJS,
        sh.toJS,
      ],
    );
    return jsCanvas;
  } catch (e) {
    debugPrint('Video crop failed: $e');
    return null;
  }
}

Future<String?> detectFromActiveVideo({
  Size previewSize = Size.zero,
  Rect cropInPreview = Rect.zero,
}) async {
  // Never decode the full camera frame — wait until the white-rect crop is known.
  if (cropInPreview.width <= 8 ||
      cropInPreview.height <= 8 ||
      previewSize.width <= 0 ||
      previewSize.height <= 0) {
    return null;
  }

  final detectorCtor = globalContext.getProperty('BarcodeDetector'.toJS);
  if (detectorCtor == null) return null;

  final video = _firstLiveVideo();
  if (video == null) return null;

  final vwRaw = video.getProperty('videoWidth'.toJS)?.dartify();
  final vhRaw = video.getProperty('videoHeight'.toJS)?.dartify();
  if (vwRaw is! num || vhRaw is! num || vwRaw < 8 || vhRaw < 8) return null;
  final vw = vwRaw.toDouble();
  final vh = vhRaw.toDouble();

  final detector = _makeDetector(detectorCtor);
  if (detector == null) return null;

  final detectFn = detector.getProperty('detect'.toJS);
  if (detectFn == null) return null;

  final videoCrop = _previewRectToVideo(cropInPreview, previewSize, vw, vh);
  if (videoCrop.width < 8 || videoCrop.height < 8) return null;

  final cropped = _cropVideoToCanvas(video, vw, vh, videoCrop);
  if (cropped == null) return null;
  final JSAny source = cropped;

  final result = (detectFn as JSFunction).callAsFunction(detector, source);
  if (result == null) return null;

  final list = await (result as JSPromise).toDart;
  if (list == null) return null;

  final dartList = list.dartify();
  if (dartList is! List || dartList.isEmpty) return null;

  for (final item in dartList) {
    if (item is Map) {
      final raw = item['rawValue']?.toString().trim();
      if (raw != null && raw.isNotEmpty) return raw;
    }
  }
  return null;
}
