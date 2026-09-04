import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:pwa/utils/barcode_validator.dart';

/// Extra live barcode polling for web.
///
/// mobile_scanner decodes the full camera frame, so a 1D code that only covers
/// a small part of a 1080p frame ends up with bars 1–2 pixels wide and never
/// decodes. This poller crops a wide band of the preview, scales it up, and
/// uses BarcodeDetector and/or zxing-wasm.
class WebBarcodePoller {
  Timer? _timer;
  bool _busy = false;
  void Function(String value)? _onCode;
  Size _previewSize = Size.zero;
  Rect _cropInPreview = Rect.zero;

  bool get isRunning => _timer != null;

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
    Duration interval = const Duration(milliseconds: 120),
  }) {
    stop();
    _CropDecoder.instance.resetSession();
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

Future<String?> detectFromActiveVideo({
  Size previewSize = Size.zero,
  Rect cropInPreview = Rect.zero,
}) async {
  if (cropInPreview.width <= 8 ||
      cropInPreview.height <= 8 ||
      previewSize.width <= 0 ||
      previewSize.height <= 0) {
    return null;
  }

  final decoder = _CropDecoder.instance;
  if (!decoder.hasBackend) {
    decoder.ensureBackend();
    return null;
  }

  final video = _firstLiveVideo();
  if (video == null) return null;

  final vwRaw = video.getProperty('videoWidth'.toJS)?.dartify();
  final vhRaw = video.getProperty('videoHeight'.toJS)?.dartify();
  if (vwRaw is! num || vhRaw is! num || vwRaw < 8 || vhRaw < 8) return null;
  final vw = vwRaw.toDouble();
  final vh = vhRaw.toDouble();

  final videoCrop = _previewRectToVideo(cropInPreview, previewSize, vw, vh);
  if (videoCrop.width < 8 || videoCrop.height < 8) return null;

  return decoder.decode(video: video, videoCrop: videoCrop);
}

const List<String> _nativeLinearFormats = <String>[
  'ean_13',
  'ean_8',
  'upc_a',
  'upc_e',
  'code_128',
  'code_39',
  'code_93',
  'codabar',
  'itf',
];

const List<String> _zxingLinearFormats = <String>[
  'EAN13',
  'EAN8',
  'UPCA',
  'UPCE',
  'ISBN',
  'Code128',
  'Code39',
  'Code93',
  'Codabar',
  'ITF',
  'ITF14',
  'DataBar',
  'DataBarExp',
];

class _CropDecoder {
  _CropDecoder._();

  static final _CropDecoder instance = _CropDecoder._();

  static const int _budgetMs = 240;
  static const double _upscaleTargetWidth = 2000;
  static const int _nativeGracePeriod = 40;
  static const String _zxingScriptId = 'mobile-scanner-zxing-wasm';
  static const String _zxingScriptUrl =
      'https://cdn.jsdelivr.net/npm/zxing-wasm@3.1.1/dist/iife/reader/index.js';

  JSObject? _canvas;
  JSObject? _context;
  JSObject? _detector;
  bool _detectorUnusable = false;
  bool _zxingFormatsRejected = false;
  bool _zxingRequested = false;
  int _attempts = 0;
  int _decodes = 0;
  int _nativeAttempts = 0;
  int _nativeMisses = 0;
  String? _lastError;

  JSAny? get _detectorCtor => globalContext.getProperty('BarcodeDetector'.toJS);

  bool get _nativeAvailable => !_detectorUnusable && _detectorCtor != null;

  JSObject? get _zxingModule {
    final module = globalContext.getProperty('ZXingWASM'.toJS);
    if (module == null) return null;
    final object = module as JSObject;
    return object.getProperty('readBarcodes'.toJS) == null ? null : object;
  }

  bool get hasBackend => _nativeAvailable || _zxingModule != null;

  void ensureBackend() {
    if (_zxingModule != null || _zxingRequested) return;
    if (_nativeAvailable &&
        (_decodes > 0 || _nativeAttempts < _nativeGracePeriod)) {
      return;
    }
    _loadZxing();
  }

  void resetSession() {
    _attempts = 0;
    _decodes = 0;
    _nativeAttempts = 0;
    _lastError = null;
  }

  void _loadZxing() {
    _zxingRequested = true;
    try {
      final document = globalContext.getProperty('document'.toJS) as JSObject;
      final existing = document.callMethod(
        'querySelector'.toJS,
        'script#$_zxingScriptId'.toJS,
      );
      if (existing != null) return;

      final script =
          document.callMethod('createElement'.toJS, 'script'.toJS) as JSObject?;
      final head = document.getProperty('head'.toJS) as JSObject?;
      if (script == null || head == null) return;

      script
        ..setProperty('id'.toJS, _zxingScriptId.toJS)
        ..setProperty('async'.toJS, true.toJS)
        ..setProperty('crossOrigin'.toJS, 'anonymous'.toJS)
        ..setProperty('src'.toJS, _zxingScriptUrl.toJS)
        ..setProperty(
          'onerror'.toJS,
          (JSAny _) {
            _lastError = 'zxing-wasm failed to load';
            debugPrint('zxing-wasm script failed to load');
          }.toJS,
        );
      head.callMethod('appendChild'.toJS, script);
      debugPrint('Loading zxing-wasm as a fallback decoder');
    } catch (e) {
      _lastError = 'zxing load: $e';
      debugPrint('Could not load zxing-wasm: $e');
    }
  }

  Future<String?> decode({
    required JSObject video,
    required Rect videoCrop,
  }) async {
    final clock = Stopwatch()..start();
    _attempts++;
    ensureBackend();

    for (final scale in _scalesFor(videoCrop)) {
      final drawn = _drawCrop(video, videoCrop, scale);
      if (drawn == null) continue;

      final native = await _detectNative(drawn);
      if (native != null) {
        _decodes++;
        return native;
      }
      if (clock.elapsedMilliseconds > _budgetMs) return null;

      final zxing = await _detectZxing(drawn, invert: true);
      if (zxing != null) {
        _decodes++;
        if (_nativeAvailable && ++_nativeMisses >= 2) {
          _detectorUnusable = true;
          _detector = null;
          debugPrint('BarcodeDetector keeps missing codes, using zxing only');
        }
        return zxing;
      }
      if (clock.elapsedMilliseconds > _budgetMs) return null;

      // Second pass without invert in case tryInvert confused a clean code.
      final zxingPlain = await _detectZxing(drawn, invert: false);
      if (zxingPlain != null) {
        _decodes++;
        return zxingPlain;
      }
    }
    return null;
  }

  List<double> _scalesFor(Rect videoCrop) {
    final upscale =
        (_upscaleTargetWidth / videoCrop.width).clamp(1.0, 4.5).toDouble();
    if (upscale <= 1.05) return const <double>[1.0, 1.35];
    if (upscale <= 2.0) return <double>[1.0, 1.4, upscale];
    return <double>[1.0, upscale * 0.55, upscale * 0.8, upscale];
  }

  _DrawnCrop? _drawCrop(JSObject video, Rect videoCrop, double scale) {
    try {
      final canvas = _ensureCanvas();
      final context = _context;
      if (canvas == null || context == null) return null;

      final sw = videoCrop.width;
      final sh = videoCrop.height;
      final dw = (sw * scale).round();
      final dh = (sh * scale).round();
      if (dw < 8 || dh < 8) return null;

      canvas.setProperty('width'.toJS, dw.toJS);
      canvas.setProperty('height'.toJS, dh.toJS);
      context.setProperty('imageSmoothingEnabled'.toJS, true.toJS);
      context.setProperty('imageSmoothingQuality'.toJS, 'high'.toJS);

      context.callMethodVarArgs('drawImage'.toJS, <JSAny>[
        video,
        videoCrop.left.toJS,
        videoCrop.top.toJS,
        sw.toJS,
        sh.toJS,
        0.toJS,
        0.toJS,
        dw.toJS,
        dh.toJS,
      ]);

      return _DrawnCrop(canvas: canvas, width: dw, height: dh);
    } catch (e) {
      debugPrint('Barcode crop failed: $e');
      return null;
    }
  }

  JSObject? _ensureCanvas() {
    final existing = _canvas;
    if (existing != null) return existing;

    final document = globalContext.getProperty('document'.toJS) as JSObject;
    final canvas = document.callMethod('createElement'.toJS, 'canvas'.toJS);
    if (canvas == null) return null;
    final jsCanvas = canvas as JSObject;

    final attributes = JSObject()
      ..setProperty('willReadFrequently'.toJS, true.toJS);
    final context =
        jsCanvas.callMethodVarArgs('getContext'.toJS, <JSAny>['2d'.toJS, attributes]);
    if (context == null) return null;

    _canvas = jsCanvas;
    _context = context as JSObject;
    return jsCanvas;
  }

  Future<String?> _detectNative(_DrawnCrop crop) async {
    final detector = await _nativeDetector();
    if (detector == null) return null;
    _nativeAttempts++;
    try {
      final detect = detector.getProperty('detect'.toJS);
      if (detect == null) return null;
      final result = (detect as JSFunction).callAsFunction(detector, crop.canvas);
      if (result == null) return null;
      final list = await (result as JSPromise).toDart;
      return _firstLinearValue(list?.dartify(), rawKey: 'rawValue');
    } catch (e) {
      _lastError = 'detector: $e';
      debugPrint('BarcodeDetector detect failed: $e');
      return null;
    }
  }

  Future<JSObject?> _nativeDetector() async {
    if (_detector != null) return _detector;
    if (_detectorUnusable) return null;

    final ctor = _detectorCtor;
    if (ctor == null) return null;

    final formats = await _usableNativeFormats(ctor);
    if (formats.isEmpty) {
      _detectorUnusable = true;
      return null;
    }

    try {
      final options = JSObject()
        ..setProperty(
          'formats'.toJS,
          formats.map((f) => f.toJS).toList().toJS,
        );
      _detector = (ctor as JSFunction).callAsConstructor(options) as JSObject;
    } catch (_) {
      try {
        _detector = (ctor as JSFunction).callAsConstructor() as JSObject;
      } catch (e) {
        _detectorUnusable = true;
        debugPrint('BarcodeDetector unavailable: $e');
      }
    }
    return _detector;
  }

  Future<List<String>> _usableNativeFormats(JSAny ctor) async {
    try {
      final getSupported =
          (ctor as JSObject).getProperty('getSupportedFormats'.toJS);
      if (getSupported == null) return _nativeLinearFormats;
      final result = (getSupported as JSFunction).callAsFunction(ctor);
      if (result == null) return _nativeLinearFormats;
      final supported = (await (result as JSPromise).toDart)?.dartify();
      if (supported is! List) return _nativeLinearFormats;
      final available = supported.map((e) => '$e').toSet();
      return _nativeLinearFormats.where(available.contains).toList();
    } catch (_) {
      return _nativeLinearFormats;
    }
  }

  Future<String?> _detectZxing(_DrawnCrop crop, {bool invert = false}) async {
    final module = _zxingModule;
    final context = _context;
    if (module == null || context == null) return null;

    try {
      final imageData = context.callMethodVarArgs('getImageData'.toJS, <JSAny>[
        0.toJS,
        0.toJS,
        crop.width.toJS,
        crop.height.toJS,
      ]);
      if (imageData == null) return null;

      final options = JSObject()
        ..setProperty('tryHarder'.toJS, true.toJS)
        ..setProperty('tryRotate'.toJS, true.toJS)
        ..setProperty('tryInvert'.toJS, invert.toJS)
        ..setProperty('maxNumberOfSymbols'.toJS, 4.toJS);
      if (!_zxingFormatsRejected) {
        options.setProperty(
          'formats'.toJS,
          _zxingLinearFormats.map((f) => f.toJS).toList().toJS,
        );
      }

      final readBarcodes = module.getProperty('readBarcodes'.toJS);
      if (readBarcodes == null) return null;
      final result = (readBarcodes as JSFunction)
          .callAsFunction(module, imageData, options);
      if (result == null) return null;

      final list = await (result as JSPromise).toDart;
      return _firstLinearValue(list?.dartify(), rawKey: 'text');
    } catch (e) {
      _lastError = 'zxing: $e';
      if (!_zxingFormatsRejected) {
        _zxingFormatsRejected = true;
        debugPrint('zxing-wasm format filter rejected, using all formats: $e');
      } else {
        debugPrint('zxing-wasm decode failed: $e');
      }
      return null;
    }
  }

  String? _firstLinearValue(Object? results, {required String rawKey}) {
    if (results is! List) return null;
    for (final item in results) {
      if (item is! Map) continue;
      if (item['isValid'] == false) continue;
      final raw = item[rawKey]?.toString().trim();
      if (raw == null || raw.isEmpty) continue;
      final format = item['format']?.toString() ?? '';
      if (_isLinearFormat(format, raw)) return raw;
    }
    return null;
  }
}

class _DrawnCrop {
  const _DrawnCrop({
    required this.canvas,
    required this.width,
    required this.height,
  });

  final JSObject canvas;
  final int width;
  final int height;
}

bool _isLinearFormat(String format, String raw) {
  final name = format.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  const matrix = <String>['qr', 'aztec', 'pdf417', 'datamatrix', 'maxicode'];
  for (final blocked in matrix) {
    if (name.contains(blocked)) return false;
  }

  if (name.contains('gs1')) return true;

  const linear = <String>[
    'ean',
    'upc',
    'isbn',
    'code128',
    'code39',
    'code93',
    'codabar',
    'itf',
    'databar',
  ];
  for (final allowed in linear) {
    if (name.contains(allowed)) return true;
  }

  if (BarcodeValidator.looksLikeGs1(raw)) return true;

  final digits = raw.replaceAll(RegExp(r'\D'), '');
  return digits.isNotEmpty &&
      digits.length == raw.length &&
      (digits.length == 8 ||
          digits.length == 12 ||
          digits.length == 13 ||
          digits.length == 14);
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
    if (jsVideo.getProperty('srcObject'.toJS) == null) continue;
    final ready = jsVideo.getProperty('readyState'.toJS)?.dartify();
    if (ready is num && ready >= 2) return jsVideo;
  }
  return null;
}

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
