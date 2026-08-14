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
    // Laptop webcams often throw OverconstrainedError for focus/zoom.
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

bool _focusSupported(Map<Object?, Object?>? caps) {
  if (caps == null) return false;
  final modes = caps['focusMode'];
  if (modes is List) {
    return modes.map((e) => '$e').any((m) => m == 'continuous' || m == 'manual' || m == 'single-shot');
  }
  return modes != null;
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

({double min, double max})? _zoomRange(Map<Object?, Object?>? caps) {
  if (caps == null) return null;
  final zoom = caps['zoom'];
  if (zoom is Map) {
    final min = zoom['min'];
    final max = zoom['max'];
    if (min is num && max is num && max > min) {
      return (min: min.toDouble(), max: max.toDouble());
    }
  }
  // Some browsers expose zoom as `{min,max}` only.
  return null;
}

WebCameraCapabilities probeWebCameraCapabilities() {
  final tracks = _liveVideoTracks();
  if (tracks.isEmpty) return const WebCameraCapabilities.unsupported();

  var supportsFocus = false;
  var supportsZoom = false;
  var supportsTorch = false;
  var zoomMin = 1.0;
  var zoomMax = 1.0;

  for (final track in tracks) {
    final caps = _capabilitiesOf(track);
    if (_focusSupported(caps)) supportsFocus = true;
    if (_torchSupported(caps)) supportsTorch = true;
    final zoom = _zoomRange(caps);
    if (zoom != null) {
      supportsZoom = true;
      zoomMin = zoom.min;
      zoomMax = zoom.max;
    }
  }

  return WebCameraCapabilities(
    supportsFocus: supportsFocus,
    supportsZoom: supportsZoom,
    supportsTorch: supportsTorch,
    zoomMin: zoomMin,
    zoomMax: zoomMax,
  );
}

Future<WebCameraCapabilities> enableContinuousCameraFocus() async {
  final caps = probeWebCameraCapabilities();
  if (!caps.supportsFocus) return caps;

  for (final track in _liveVideoTracks()) {
    final trackCaps = _capabilitiesOf(track);
    if (!_focusSupported(trackCaps)) continue;

    // Prefer continuous AF when the device advertises it.
    final modes = trackCaps?['focusMode'];
    final modeList = modes is List ? modes.map((e) => '$e').toList() : const <String>[];
    if (modeList.contains('continuous')) {
      final ok = await _applyIdeal(track, const {'focusMode': 'continuous'});
      if (!ok) {
        await _applyAdvanced(track, const {'focusMode': 'continuous'});
      }
    }
  }
  return caps;
}

/// Tap/manual focus. Uses hardware focus when available, otherwise zoom.
Future<bool> focusCameraAt(Offset normalizedPoint) async {
  final caps = probeWebCameraCapabilities();
  var changed = false;

  if (caps.supportsFocus) {
    final dy = normalizedPoint.dy.clamp(0.0, 1.0);
    final focusDistance = (1.0 - dy).clamp(0.0, 1.0);
    for (final track in _liveVideoTracks()) {
      final trackCaps = _capabilitiesOf(track);
      if (!_focusSupported(trackCaps)) continue;

      final modes = trackCaps?['focusMode'];
      final modeList = modes is List ? modes.map((e) => '$e').toList() : const <String>[];

      if (modeList.contains('manual') && trackCaps?.containsKey('focusDistance') == true) {
        changed = await _applyAdvanced(track, {
              'focusMode': 'manual',
              'focusDistance': focusDistance,
            }) ||
            changed;
      } else if (modeList.contains('single-shot')) {
        changed = await _applyIdeal(track, const {'focusMode': 'single-shot'}) || changed;
      } else if (modeList.contains('continuous')) {
        // Re-trigger continuous AF — best effort "refocus".
        changed = await _applyIdeal(track, const {'focusMode': 'continuous'}) || changed;
      }
    }
  }

  if (!changed && caps.supportsZoom) {
    // Map vertical tap to zoom: top = max zoom, bottom = min zoom.
    final t = (1.0 - normalizedPoint.dy.clamp(0.0, 1.0));
    changed = await setWebCameraZoom(t) || changed;
  }

  return changed;
}

/// [normalized] is 0..1 within the camera's zoom range.
Future<bool> setWebCameraZoom(double normalized) async {
  final caps = probeWebCameraCapabilities();
  if (!caps.supportsZoom) return false;

  final t = normalized.clamp(0.0, 1.0);
  final zoom = caps.zoomMin + (caps.zoomMax - caps.zoomMin) * t;
  var changed = false;

  for (final track in _liveVideoTracks()) {
    final trackCaps = _capabilitiesOf(track);
    if (_zoomRange(trackCaps) == null) continue;

    // Try simple constraint first, then advanced.
    final ok = await _applyIdeal(track, {'zoom': zoom});
    if (ok) {
      changed = true;
    } else {
      changed = await _applyAdvanced(track, {'zoom': zoom}) || changed;
    }
  }
  return changed;
}

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

/// True when mobile_scanner CSS-mirrors the preview (front / desktop cameras).
bool webPreviewIsMirrored() {
  final tracks = _liveVideoTracks();
  if (tracks.isEmpty) return false;
  final mode = _facingModeOf(tracks.first);
  return mode == 'user' || mode == null || mode.isEmpty;
}

bool webIsAppleMobile() => _isAppleMobileWeb();

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
