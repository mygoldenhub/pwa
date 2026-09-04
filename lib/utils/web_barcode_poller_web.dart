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
  /// Extra decode magnification when CSS zoom is used (hardware zoom = 1.0).
  double _decodeMagnify = 1.0;
  Duration _interval = const Duration(milliseconds: 80);

  bool get isRunning => _timer != null;

  void setScanRegion({
    required Size previewSize,
    required Rect cropInPreview,
    double decodeMagnify = 1.0,
  }) {
    _previewSize = previewSize;
    _cropInPreview = cropInPreview;
    _decodeMagnify = decodeMagnify <= 1.0 ? 1.0 : decodeMagnify;
  }

  void start({
    required void Function(String value) onCode,
    Size? previewSize,
    Rect? cropInPreview,
    double decodeMagnify = 1.0,
    Duration interval = const Duration(milliseconds: 80),
  }) {
    stop();
    _CropDecoder.instance.resetSession();
    _onCode = onCode;
    if (previewSize != null) _previewSize = previewSize;
    if (cropInPreview != null) _cropInPreview = cropInPreview;
    _decodeMagnify = decodeMagnify <= 1.0 ? 1.0 : decodeMagnify;
    _interval = interval;
    _timer = Timer.periodic(_interval, (_) => unawaited(_tick()));
  }

  /// Keep polling but refresh crop / magnify after a zoom change.
  void updateRegion({
    required Size previewSize,
    required Rect cropInPreview,
    double decodeMagnify = 1.0,
  }) {
    setScanRegion(
      previewSize: previewSize,
      cropInPreview: cropInPreview,
      decodeMagnify: decodeMagnify,
    );
    _CropDecoder.instance.resetSession();
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
        decodeMagnify: _decodeMagnify,
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
  double decodeMagnify = 1.0,
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

  // Landscape band first (common case), then a tall portrait band for
  // vertical / 90° barcodes — without changing native phone path.
  final crops = <Rect>[
    cropInPreview,
    _portraitDecodeBand(previewSize),
  ];

  for (final previewCrop in crops) {
    final videoCrop = _previewRectToVideo(previewCrop, previewSize, vw, vh);
    if (videoCrop.width < 8 || videoCrop.height < 8) continue;
    final hit = await decoder.decode(
      video: video,
      videoCrop: videoCrop,
      decodeMagnify: decodeMagnify,
    );
    if (hit != null && hit.isNotEmpty) return hit;
  }
  return null;
}

/// Tall center band so sideways (vertical) 1D codes still fill the crop.
Rect _portraitDecodeBand(Size preview) {
  return Rect.fromCenter(
    center: Offset(preview.width / 2, preview.height * 0.45),
    width: (preview.width * 0.42).clamp(1.0, preview.width),
    height: (preview.height * 0.78).clamp(1.0, preview.height),
  );
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

  static const int _budgetMs = 300;
  static const double _upscaleTargetWidth = 2000;
  static const int _nativeGracePeriod = 40;
  static const String _zxingScriptId = 'mobile-scanner-zxing-wasm';
  static const String _zxingScriptUrl =
      'https://cdn.jsdelivr.net/npm/zxing-wasm@3.1.1/dist/iife/reader/index.js';

  JSObject? _canvas;
  JSObject? _context;
  JSObject? _auxCanvas;
  JSObject? _auxContext;
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
    double decodeMagnify = 1.0,
  }) async {
    final clock = Stopwatch()..start();
    _attempts++;
    ensureBackend();

    final scales = _scalesFor(videoCrop, decodeMagnify);
    for (var i = 0; i < scales.length; i++) {
      final drawn = _drawCrop(video, videoCrop, scales[i]);
      if (drawn == null) continue;

      // Fast path: upright crop (covers mild tilt / upside-down via engine).
      final primary = await _detectPrimary(drawn);
      if (primary != null) {
        _decodes++;
        return primary;
      }
      if (clock.elapsedMilliseconds > _budgetMs) return null;

      // Orientation fallbacks only after the first scale misses — keeps the
      // common upright path fast, then helps 90° / mirrored / steep skew.
      if (i == 0) {
        final oriented = await _detectOrientationFallbacks(
          drawn,
          clock: clock,
        );
        if (oriented != null) {
          _decodes++;
          return oriented;
        }
        if (clock.elapsedMilliseconds > _budgetMs) return null;
      }
    }
    return null;
  }

  Future<String?> _detectPrimary(_DrawnCrop drawn) async {
    final native = await _detectNative(drawn);
    if (native != null) {
      return native;
    }

    final zxing = await _detectZxing(drawn, invert: true);
    if (zxing != null) {
      if (_nativeAvailable && ++_nativeMisses >= 2) {
        _detectorUnusable = true;
        _detector = null;
        debugPrint('BarcodeDetector keeps missing codes, using zxing only');
      }
      return zxing;
    }

    return _detectZxing(drawn, invert: false);
  }

  /// Explicit 90°/270° and mirror passes for sideways / glass-reflected labels.
  /// zxing tryRotate helps small skew; canvas turns catch vertical barcodes.
  Future<String?> _detectOrientationFallbacks(
    _DrawnCrop drawn, {
    required Stopwatch clock,
  }) async {
    for (final turns in const <int>[1, 3]) {
      if (clock.elapsedMilliseconds > _budgetMs) return null;
      final rotated = _transformCrop(drawn, quarterTurns: turns);
      if (rotated == null) continue;
      final hit = await _detectZxing(rotated, invert: false) ??
          await _detectZxing(rotated, invert: true);
      if (hit != null) return hit;
    }

    if (clock.elapsedMilliseconds > _budgetMs) return null;
    final mirrored = _transformCrop(drawn, mirrorX: true);
    if (mirrored == null) return null;
    return await _detectZxing(mirrored, invert: false) ??
        await _detectZxing(mirrored, invert: true);
  }

  List<double> _scalesFor(Rect videoCrop, double decodeMagnify) {
    final mag = decodeMagnify <= 1.0 ? 1.0 : decodeMagnify;
    final targetW = (_upscaleTargetWidth * mag).clamp(1200.0, 2800.0);
    final upscale =
        (targetW / videoCrop.width).clamp(1.0, 5.0).toDouble();
    if (upscale <= 1.05) return <double>[1.0, 1.35 * mag.clamp(1.0, 2.0)];
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

  /// Rotate (quarter turns clockwise) and/or mirror a drawn crop onto an aux canvas.
  _DrawnCrop? _transformCrop(
    _DrawnCrop source, {
    int quarterTurns = 0,
    bool mirrorX = false,
  }) {
    try {
      final turns = quarterTurns % 4;
      if (turns == 0 && !mirrorX) return source;

      final aux = _ensureAuxCanvas();
      final ctx = _auxContext;
      if (aux == null || ctx == null) return null;

      final swap = turns.isOdd;
      final dw = swap ? source.height : source.width;
      final dh = swap ? source.width : source.height;
      if (dw < 8 || dh < 8) return null;

      aux.setProperty('width'.toJS, dw.toJS);
      aux.setProperty('height'.toJS, dh.toJS);
      ctx.setProperty('imageSmoothingEnabled'.toJS, true.toJS);
      ctx.setProperty('imageSmoothingQuality'.toJS, 'high'.toJS);

      ctx.callMethod('save'.toJS);
      // Map source into destination with rotation about center.
      if (turns == 1) {
        ctx.callMethodVarArgs('translate'.toJS, <JSAny>[dw.toJS, 0.toJS]);
        ctx.callMethod('rotate'.toJS, (1.5707963267948966).toJS); // π/2
      } else if (turns == 2) {
        ctx.callMethodVarArgs('translate'.toJS, <JSAny>[dw.toJS, dh.toJS]);
        ctx.callMethod('rotate'.toJS, (3.141592653589793).toJS); // π
      } else if (turns == 3) {
        ctx.callMethodVarArgs('translate'.toJS, <JSAny>[0.toJS, dh.toJS]);
        ctx.callMethod('rotate'.toJS, (-1.5707963267948966).toJS);
      }
      if (mirrorX) {
        ctx.callMethodVarArgs(
          'translate'.toJS,
          <JSAny>[source.width.toJS, 0.toJS],
        );
        ctx.callMethodVarArgs('scale'.toJS, <JSAny>[(-1).toJS, 1.toJS]);
      }

      ctx.callMethodVarArgs('drawImage'.toJS, <JSAny>[
        source.canvas,
        0.toJS,
        0.toJS,
      ]);
      ctx.callMethod('restore'.toJS);

      return _DrawnCrop(canvas: aux, width: dw, height: dh);
    } catch (e) {
      debugPrint('Barcode transform failed: $e');
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

  JSObject? _ensureAuxCanvas() {
    final existing = _auxCanvas;
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

    _auxCanvas = jsCanvas;
    _auxContext = context as JSObject;
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
    if (module == null) return null;

    try {
      final ctx = crop.canvas.callMethodVarArgs(
            'getContext'.toJS,
            <JSAny>['2d'.toJS],
          ) as JSObject? ??
          _context;
      if (ctx == null) return null;

      final imageData = ctx.callMethodVarArgs('getImageData'.toJS, <JSAny>[
        0.toJS,
        0.toJS,
        crop.width.toJS,
        crop.height.toJS,
      ]);
      if (imageData == null) return null;

      final options = JSObject()
        ..setProperty('tryHarder'.toJS, true.toJS)
        // Small in-plane skew; canvas quarter-turns cover 90° / vertical labels.
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
