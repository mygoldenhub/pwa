import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui';

import 'package:pwa/utils/camera_focus_types.dart';

JSObject get _document => globalContext.getProperty('document'.toJS) as JSObject;

JSObject _jsConstraint(Map<String, Object> values) {
  final obj = JSObject();
  for (final entry in values.entries) {
    final value = entry.value;
    if (value is String) {
      obj.setProperty(entry.key.toJS, value.toJS);
    } else if (value is num) {
      obj.setProperty(entry.key.toJS, value.toJS);
    } else if (value is bool) {
      obj.setProperty(entry.key.toJS, value.toJS);
    }
  }
  return obj;
}

Future<bool> _applyConstraints(JSObject track, JSObject constraints) async {
  try {
    final result = track.callMethod('applyConstraints'.toJS, constraints);
    if (result != null) {
      await (result as JSPromise).toDart;
    }
    return true;
  } catch (_) {
    // Laptop webcams often throw OverconstrainedError for focus.
    return false;
  }
}

Future<bool> _applyAdvanced(JSObject track, Map<String, Object> advanced) {
  final constraints = JSObject();
  constraints.setProperty('advanced'.toJS, <JSAny>[_jsConstraint(advanced)].toJS);
  return _applyConstraints(track, constraints);
}

Future<bool> _applyIdeal(JSObject track, Map<String, Object> ideal) {
  final constraints = JSObject();
  for (final entry in ideal.entries) {
    final value = entry.value;
    if (value is String) {
      constraints.setProperty(entry.key.toJS, value.toJS);
    } else if (value is num) {
      constraints.setProperty(entry.key.toJS, value.toJS);
    } else if (value is bool) {
      constraints.setProperty(entry.key.toJS, value.toJS);
    }
  }
  return _applyConstraints(track, constraints);
}

/// `advanced: [{...}]` with a nested `pointsOfInterest` entry.
Future<bool> _applyAdvancedWithPoint(
  JSObject track,
  Map<String, Object> advanced,
  Offset point,
) {
  final set = _jsConstraint(advanced);
  final jsPoint = JSObject()
    ..setProperty('x'.toJS, point.dx.toJS)
    ..setProperty('y'.toJS, point.dy.toJS);
  set.setProperty('pointsOfInterest'.toJS, <JSAny>[jsPoint].toJS);

  final constraints = JSObject();
  constraints.setProperty('advanced'.toJS, <JSAny>[set].toJS);
  return _applyConstraints(track, constraints);
}

bool _pointOfInterestSupported() {
  try {
    final nav = globalContext.getProperty('navigator'.toJS) as JSObject?;
    final devices = nav?.getProperty('mediaDevices'.toJS) as JSObject?;
    final supported = devices?.callMethod('getSupportedConstraints'.toJS);
    final dart = supported?.dartify();
    return dart is Map && dart['pointsOfInterest'] == true;
  } catch (_) {
    return false;
  }
}

int _jsLength(JSObject list) {
  final value = list.getProperty('length'.toJS)?.dartify();
  if (value is num) return value.toInt();
  return 0;
}

bool _isLiveTrack(JSObject track) {
  return track.getProperty('readyState'.toJS)?.dartify() == 'live';
}

List<JSObject> _liveVideoTracks() {
  final tracks = <JSObject>[];
  final videos = _document.callMethod('querySelectorAll'.toJS, 'video'.toJS);
  if (videos == null) return tracks;

  final list = videos as JSObject;
  final length = _jsLength(list);

  for (var i = 0; i < length; i++) {
    final video = list.callMethod('item'.toJS, i.toJS);
    if (video == null) continue;

    final stream = (video as JSObject).getProperty('srcObject'.toJS);
    if (stream == null) continue;

    final videoTracks = (stream as JSObject).callMethod('getVideoTracks'.toJS);
    if (videoTracks == null) continue;

    final trackList = videoTracks as JSObject;
    final trackCount = _jsLength(trackList);

    for (var t = 0; t < trackCount; t++) {
      final track = trackList.getProperty(t.toJS);
      if (track == null) continue;
      final jsTrack = track as JSObject;
      if (_isLiveTrack(jsTrack)) tracks.add(jsTrack);
    }
  }
  return tracks;
}

Map<Object?, Object?>? _capabilitiesOf(JSObject track) {
  try {
    final caps = track.callMethod('getCapabilities'.toJS);
    final dart = caps?.dartify();
    if (dart is Map) return dart.cast<Object?, Object?>();
  } catch (_) {}
  return null;
}

List<String> _focusModes(Map<Object?, Object?>? caps) {
  final modes = caps?['focusMode'];
  if (modes is List) return modes.map((e) => '$e').toList();
  return const <String>[];
}

bool _focusSupported(Map<Object?, Object?>? caps) {
  if (caps == null) return false;
  final modes = caps['focusMode'];
  if (modes is List) {
    return modes.map((e) => '$e').any((m) => m == 'continuous' || m == 'manual' || m == 'single-shot');
  }
  return modes != null;
}

WebFocusRange? _focusRange(Map<Object?, Object?>? caps) {
  if (!_focusModes(caps).contains('manual')) return null;
  final range = caps?['focusDistance'];
  if (range is! Map) return null;
  final min = range['min'];
  final max = range['max'];
  if (min is! num || max is! num || max <= min) return null;
  final step = range['step'];
  return WebFocusRange(
    min: min.toDouble(),
    max: max.toDouble(),
    step: step is num ? step.toDouble() : 0,
  );
}

/// Live tracks that can be focused. Front cameras are skipped: they are fixed
/// focus on most devices and would only soak up the constraint calls.
List<JSObject> _focusableTracks() {
  return [
    for (final track in _liveVideoTracks())
      if (_facingModeOf(track) != 'user' && _focusSupported(_capabilitiesOf(track)))
        track,
  ];
}

bool _torchSupported(Map<Object?, Object?>? caps) {
  if (caps == null) return false;
  if (caps.containsKey('torch')) return true;
  final fill = caps['fillLightMode'] ?? caps['fillLightModes'];
  if (fill is List) {
    return fill.map((e) => '$e'.toLowerCase()).any((m) => m == 'torch' || m == 'flash');
  }
  return false;
}

bool _zoomSupported(Map<Object?, Object?>? caps) {
  if (caps == null) return false;
  final zoom = caps['zoom'];
  if (zoom is Map) {
    final min = zoom['min'];
    final max = zoom['max'];
    return min is num && max is num && max > min;
  }
  return caps.containsKey('zoom');
}

String? _facingModeOf(JSObject track) {
  try {
    final settings = track.callMethod('getSettings'.toJS);
    final dart = settings?.dartify();
    if (dart is Map) {
      final mode = dart['facingMode']?.toString().trim();
      if (mode != null && mode.isNotEmpty) return mode;
    }
  } catch (_) {}
  return null;
}

bool _isAppleMobileWeb() {
  try {
    final nav = globalContext.getProperty('navigator'.toJS) as JSObject?;
    if (nav == null) return false;
    final ua = nav.getProperty('userAgent'.toJS)?.dartify()?.toString() ?? '';
    final platform = nav.getProperty('platform'.toJS)?.dartify()?.toString() ?? '';
    final iOSDevice = ua.contains('iPhone') || ua.contains('iPad') || ua.contains('iPod') || platform.contains('iPhone');
    final touch = nav.getProperty('maxTouchPoints'.toJS)?.dartify();
    final iPadOs = platform.contains('Mac') && touch is num && touch > 1;
    return iOSDevice || iPadOs;
  } catch (_) {
    return false;
  }
}

WebCameraCapabilities probeWebCameraCapabilities() {
  final tracks = _liveVideoTracks();
  if (tracks.isEmpty) return const WebCameraCapabilities.unsupported();

  var supportsFocus = false;
  var supportsTorch = false;
  var supportsFocusDistance = false;
  var supportsZoom = false;

  for (final track in tracks) {
    final caps = _capabilitiesOf(track);
    if (_focusSupported(caps)) supportsFocus = true;
    if (_torchSupported(caps)) supportsTorch = true;
    if (_focusRange(caps) != null) supportsFocusDistance = true;
    if (_zoomSupported(caps)) supportsZoom = true;
  }

  return WebCameraCapabilities(
    supportsFocus: supportsFocus,
    supportsTorch: supportsTorch,
    supportsFocusDistance: supportsFocusDistance,
    supportsZoom: supportsZoom,
  );
}

Future<WebCameraCapabilities> enableContinuousCameraFocus() async {
  final caps = probeWebCameraCapabilities();
  if (!caps.supportsFocus) return caps;
  await requestWebAutoFocus();
  return caps;
}

/// Hand the lens back to the camera's own autofocus, aimed at [point] when the
/// browser supports a point of interest (normalized 0..1 in camera space).
///
/// The `advanced` form is tried first: Chrome ignores a plain `focusMode`
/// constraint on most Android cameras.
Future<bool> requestWebAutoFocus({Offset? point}) async {
  var changed = false;
  final withPoint = point != null && _pointOfInterestSupported();

  for (final track in _focusableTracks()) {
    final modes = _focusModes(_capabilitiesOf(track));
    final mode = modes.contains('continuous')
        ? 'continuous'
        : modes.contains('single-shot')
            ? 'single-shot'
            : null;
    if (mode == null) continue;

    var ok = false;
    if (withPoint) {
      final clamped = Offset(
        point.dx.clamp(0.0, 1.0),
        point.dy.clamp(0.0, 1.0),
      );
      ok = await _applyAdvancedWithPoint(track, {'focusMode': mode}, clamped);
    }
    ok = ok || await _applyAdvanced(track, {'focusMode': mode});
    ok = ok || await _applyIdeal(track, {'focusMode': mode});
    changed = changed || ok;
  }
  return changed;
}

/// The lens positions the camera will accept, or null when it cannot be driven
/// manually.
WebFocusRange? webFocusRange() {
  for (final track in _liveVideoTracks()) {
    if (_facingModeOf(track) == 'user') continue;
    final range = _focusRange(_capabilitiesOf(track));
    if (range != null) return range;
  }
  return null;
}

/// Park the lens at an explicit distance, for a focus sweep.
Future<bool> setWebFocusDistance(double distance) async {
  var changed = false;
  for (final track in _focusableTracks()) {
    final range = _focusRange(_capabilitiesOf(track));
    if (range == null) continue;
    final value = distance.clamp(range.min, range.max);
    final ok = await _applyAdvanced(track, {
      'focusMode': 'manual',
      'focusDistance': value,
    });
    changed = changed || ok;
  }
  return changed;
}

/// Tap to focus. Refocuses on [normalizedPoint] (0..1 in camera space).
Future<bool> focusCameraAt(Offset normalizedPoint) =>
    requestWebAutoFocus(point: normalizedPoint);

/// Set flashlight when the browser camera exposes a torch constraint.
/// Chrome on Android requires the `advanced: [{ torch }]` form.
Future<bool> setWebTorch(bool enabled) async {
  var changed = false;
  for (final track in _liveVideoTracks()) {
    final caps = _capabilitiesOf(track);
    final facing = _facingModeOf(track);
    // Front cameras almost never have a torch — skip them so we don't fail
    // the rear-camera track by applying a bad constraint first.
    if (facing == 'user') continue;

    final advertised = _torchSupported(caps);
    if (!advertised && caps != null && caps.isNotEmpty && facing != 'environment') {
      continue;
    }

    // Chrome Android: advanced torch constraint is the one that actually works.
    var ok = await _applyAdvanced(track, {'torch': enabled});
    if (!ok) ok = await _applyIdeal(track, {'torch': enabled});
    if (!ok && advertised) {
      ok = await _applyAdvanced(track, {'fillLightMode': enabled ? 'torch' : 'off'});
    }
    if (ok) changed = true;
  }
  return changed;
}

Future<bool> webTorchSupported() async {
  if (_isAppleMobileWeb()) return false;
  return probeWebCameraCapabilities().supportsTorch;
}

bool webZoomSupported() => probeWebCameraCapabilities().supportsZoom;

double? webZoomLevel() {
  for (final track in _liveVideoTracks()) {
    if (_facingModeOf(track) == 'user') continue;
    try {
      final settings = track.callMethod('getSettings'.toJS)?.dartify();
      if (settings is Map && settings['zoom'] is num) {
        return (settings['zoom'] as num).toDouble();
      }
    } catch (_) {}
  }
  return null;
}

/// Apply digital zoom when the barcode is too small in the frame.
Future<bool> setWebZoom(double level) async {
  var changed = false;
  for (final track in _focusableTracks()) {
    final caps = _capabilitiesOf(track);
    final zoom = caps?['zoom'];
    if (zoom is! Map) continue;
    final min = zoom['min'];
    final max = zoom['max'];
    if (min is! num || max is! num || max <= min) continue;
    final value = level.clamp(min.toDouble(), max.toDouble());
    var ok = await _applyAdvanced(track, {'zoom': value});
    ok = ok || await _applyIdeal(track, {'zoom': value});
    changed = changed || ok;
  }
  return changed;
}

/// True when mobile_scanner CSS-mirrors the preview (front / desktop cameras).
bool webPreviewIsMirrored() {
  final tracks = _liveVideoTracks();
  if (tracks.isEmpty) return false;
  final mode = _facingModeOf(tracks.first);
  return mode == 'user' || mode == null || mode.isEmpty;
}

bool webIsAppleMobile() => _isAppleMobileWeb();

/// Keep the preview playing inline.
///
/// mobile_scanner never sets `playsinline`, and Safari on iPhone refuses to
/// play a video element inline without it — the stream is live but the element
/// never produces frames, so every decoder sees nothing at all.
void ensureWebVideoPlaysInline() {
  try {
    final videos = _document.callMethod('querySelectorAll'.toJS, 'video'.toJS);
    if (videos == null) return;
    final list = videos as JSObject;
    final length = _jsLength(list);
    for (var i = 0; i < length; i++) {
      final video = list.callMethod('item'.toJS, i.toJS);
      if (video == null) continue;
      final jsVideo = video as JSObject;
      if (jsVideo.getProperty('srcObject'.toJS) == null) continue;

      jsVideo
        ..setProperty('playsInline'.toJS, true.toJS)
        ..setProperty('muted'.toJS, true.toJS)
        ..setProperty('autoplay'.toJS, true.toJS);
      jsVideo.callMethodVarArgs(
        'setAttribute'.toJS,
        <JSAny>['playsinline'.toJS, 'true'.toJS],
      );
      jsVideo.callMethodVarArgs(
        'setAttribute'.toJS,
        <JSAny>['webkit-playsinline'.toJS, 'true'.toJS],
      );

      if (jsVideo.getProperty('paused'.toJS)?.dartify() != true) continue;
      final played = jsVideo.callMethod('play'.toJS);
      if (played == null) continue;
      // A rejected play() is expected while the tab is backgrounded.
      unawaited((played as JSPromise).toDart.catchError((Object _) => null));
    }
  } catch (_) {}
}

/// CSS digital zoom for browsers that cannot drive the camera zoom constraint.
/// 1.0 is identity; 2.0 magnifies the center of the live preview.
double _cssZoom = 1.0;

/// Optical / digital zoom via MediaTrackConstraints when the camera exposes
/// a `zoom` capability (Chrome on many Android phones). [multiplier] is 1.0
/// for the widest view and 2.0 for 2x. Returns false when the track cannot
/// be zoomed, so callers can fall back to CSS.
Future<bool> setWebZoomMultiplier(double multiplier) async {
  final factor = multiplier <= 1.0 ? 1.0 : 2.0;
  var changed = false;
  for (final track in _focusableTracks()) {
    final caps = _capabilitiesOf(track);
    final zoom = caps?['zoom'];
    if (zoom is! Map) continue;
    final min = zoom['min'];
    final max = zoom['max'];
    if (min is! num || max is! num || max <= min) continue;
    final target = (min.toDouble() * factor).clamp(min.toDouble(), max.toDouble());
    var ok = await _applyAdvanced(track, {'zoom': target});
    ok = ok || await _applyIdeal(track, {'zoom': target});
    changed = changed || ok;
  }
  return changed;
}

void applyWebVideoPreviewStyle({double? cssZoom}) {
  if (cssZoom != null) _cssZoom = cssZoom <= 1.0 ? 1.0 : cssZoom;
  try {
    final videos = _document.callMethod('querySelectorAll'.toJS, 'video'.toJS);
    if (videos == null) return;
    final list = videos as JSObject;
    final length = _jsLength(list);
    for (var i = 0; i < length; i++) {
      final video = list.callMethod('item'.toJS, i.toJS);
      if (video == null) continue;
      final jsVideo = video as JSObject;
      final stream = jsVideo.getProperty('srcObject'.toJS);
      if (stream == null) continue;
      final style = jsVideo.getProperty('style'.toJS);
      if (style == null) continue;
      final jsStyle = style as JSObject;
      final scale = _cssZoom;
      // Replace plugin CSS (scaleX(-1)) so Flutter Transform is not needed.
      // CSS scale is the web 1x/2x control: MediaTrack zoom is unsupported
      // on most laptop webcams.
      jsStyle.setProperty(
        'transform'.toJS,
        (scale <= 1.0 ? 'none' : 'scale($scale)').toJS,
      );
      jsStyle.setProperty('transformOrigin'.toJS, 'center center'.toJS);
      jsStyle.setProperty('objectFit'.toJS, 'cover'.toJS);
      jsStyle.setProperty('width'.toJS, '100%'.toJS);
      jsStyle.setProperty('height'.toJS, '100%'.toJS);
      final parent = jsVideo.getProperty('parentElement'.toJS);
      if (parent != null) {
        final parentStyle = (parent as JSObject).getProperty('style'.toJS);
        if (parentStyle != null) {
          (parentStyle as JSObject).setProperty('overflow'.toJS, 'hidden'.toJS);
        }
      }
    }
  } catch (_) {}
}

/// Stop live camera tracks and detach them from <video> elements.
/// Needed because mobile_scanner on web often leaves getUserMedia running,
/// which blocks the next visit from opening the camera.
Future<void> releaseWebCameraTracks() async {
  try {
    for (final track in _liveVideoTracks()) {
      try {
        track.callMethod('stop'.toJS);
      } catch (_) {}
    }

    final videos = _document.callMethod('querySelectorAll'.toJS, 'video'.toJS);
    if (videos == null) return;
    final list = videos as JSObject;
    final length = _jsLength(list);
    for (var i = 0; i < length; i++) {
      final video = list.callMethod('item'.toJS, i.toJS);
      if (video == null) continue;
      final jsVideo = video as JSObject;
      try {
        jsVideo.callMethod('pause'.toJS);
      } catch (_) {}
      try {
        jsVideo.setProperty('srcObject'.toJS, null);
      } catch (_) {}
    }
  } catch (_) {
    // Best-effort cleanup — never block leaving the scan page.
  }
}
