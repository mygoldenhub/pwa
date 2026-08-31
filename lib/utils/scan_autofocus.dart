import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:pwa/utils/camera_focus.dart';

/// User-facing focus guidance shown below the camera preview.
enum ScanFocusHint {
  ready,
  searching,
  moveCloser,
  tapToRefocus,
}

/// Keeps the web camera focused on the framed barcode.
///
/// Browsers only expose "please autofocus", and a camera pointed at a barcode
/// held in the hand routinely locks onto the background instead — the bars are
/// low contrast while they are blurred, so the camera has no reason to hunt for
/// them. When that happens this walks the lens through its close range and
/// keeps the position where the framed region looked sharpest, which is what a
/// contrast-detect autofocus does.
class ScanAutoFocus {
  ScanAutoFocus({
    required this.focusScore,
    required this.pointOfInterest,
    this.onSearchingChanged,
    this.onHintChanged,
  });

  /// Sharpness of the framed region, or null while it cannot be measured.
  final double? Function() focusScore;

  /// Where to focus, normalized 0..1 in camera space.
  final Offset Function() pointOfInterest;

  /// Called when a focus sweep starts and ends, for the on-screen hint.
  final void Function(bool searching)? onSearchingChanged;

  final void Function(ScanFocusHint hint)? onHintChanged;

  /// Above this the framed region is sharp enough to decode.
  static const double _sharpEnough = 14;

  /// Time for the lens to move and the poller to measure the new frame.
  static const Duration _dwell = Duration(milliseconds: 400);
  static const Duration _settle = Duration(milliseconds: 1200);
  static const Duration _recheck = Duration(milliseconds: 700);
  static const Duration _retry = Duration(milliseconds: 2000);

  bool _running = false;
  bool _searching = false;
  bool _interrupted = false;
  double? _bestScore;
  ScanFocusHint _hint = ScanFocusHint.ready;
  int _softSweepCount = 0;
  bool _zoomApplied = false;

  bool get isSearching => _searching;

  ScanFocusHint get hint => _hint;

  void start() {
    if (!kIsWeb || _running) return;
    _running = true;
    _bestScore = null;
    _softSweepCount = 0;
    _zoomApplied = false;
    _setHint(ScanFocusHint.ready);
    unawaited(_run());
  }

  void stop() {
    _running = false;
    _interrupted = true;
    _setSearching(false);
    _setHint(ScanFocusHint.ready);
  }

  /// Refocus on a point the user tapped, and let the camera take over again.
  Future<void> refocusAt(Offset normalizedPoint) async {
    if (!kIsWeb) return;
    _interrupted = true;
    _bestScore = null;
    _softSweepCount = 0;
    _setHint(ScanFocusHint.ready);
    await requestWebAutoFocus(point: normalizedPoint);
  }

  Future<void> _run() async {
    await requestWebAutoFocus(point: pointOfInterest());
    await Future<void>.delayed(_settle);

    while (_running) {
      if (_isSharp()) {
        _setHint(ScanFocusHint.ready);
        await Future<void>.delayed(_recheck);
        continue;
      }

      final range = webFocusRange();
      // A sweep is only worth it when sharpness can be compared between lens
      // positions. Without either, re-arming autofocus is all that is left.
      if (range == null || focusScore() == null) {
        await requestWebAutoFocus(point: pointOfInterest());
        _setHint(ScanFocusHint.tapToRefocus);
        await Future<void>.delayed(_retry);
        continue;
      }

      await _sweep(range);
      if (!_running) return;
      await Future<void>.delayed(_recheck);
    }
  }

  bool _isSharp() {
    final score = focusScore();
    if (score == null) return false;
    final best = _bestScore;
    if (best != null && best > _sharpEnough) return score >= best * 0.75;
    return score >= _sharpEnough;
  }

  Future<void> _sweep(WebFocusRange range) async {
    final positions = range.sweepPositions();
    if (positions.isEmpty) {
      await requestWebAutoFocus(point: pointOfInterest());
      return;
    }

    _interrupted = false;
    _setSearching(true);
    _setHint(ScanFocusHint.searching);

    double? bestScore;
    double? bestPosition;

    for (final position in positions) {
      if (!_running || _interrupted) break;

      if (!await setWebFocusDistance(position)) {
        // The camera refused manual focus after all.
        await requestWebAutoFocus(point: pointOfInterest());
        _setSearching(false);
        return;
      }

      await Future<void>.delayed(_dwell);
      final score = focusScore();
      if (score == null) continue;

      if (bestScore == null || score > bestScore) {
        bestScore = score;
        bestPosition = position;
        continue;
      }
      // Clearly past the peak — no point driving the lens to infinity.
      if (bestScore > _sharpEnough && score < bestScore * 0.6) break;
    }

    _setSearching(false);
    if (_interrupted || !_running) return;

    if (bestPosition != null &&
        bestScore != null &&
        bestScore >= _sharpEnough) {
      // Only lock manual focus when the sweep actually found a sharp frame.
      await setWebFocusDistance(bestPosition);
      _bestScore = bestScore;
      _setHint(ScanFocusHint.ready);
    } else {
      // A failed sweep leaves the lens in a random position — hand control
      // back to continuous AF instead of parking on a blurry distance.
      await requestWebAutoFocus(point: pointOfInterest());
      _softSweepCount++;
      await _maybeZoomForSoftFrame();
      if (bestScore != null && bestScore < _sharpEnough * 0.6) {
        _setHint(ScanFocusHint.moveCloser);
      } else {
        _setHint(ScanFocusHint.tapToRefocus);
      }
    }
  }

  /// When the code stays soft after repeated sweeps, nudge digital zoom so the
  /// bars occupy more pixels — common when the barcode is small in the frame.
  Future<void> _maybeZoomForSoftFrame() async {
    if (_zoomApplied || _softSweepCount < 2) return;
    if (!webZoomSupported()) return;

    final current = webZoomLevel();
    if (current == null) return;

    final caps = probeWebCameraCapabilities();
    if (!caps.supportsZoom) return;

    final next = (current + 0.35).clamp(1.0, 3.0);
    if (next <= current + 0.05) return;

    if (await setWebZoom(next)) {
      _zoomApplied = true;
      _bestScore = null;
      _setHint(ScanFocusHint.moveCloser);
      await requestWebAutoFocus(point: pointOfInterest());
    }
  }

  void _setSearching(bool value) {
    if (_searching == value) return;
    _searching = value;
    onSearchingChanged?.call(value);
    if (value) {
      _setHint(ScanFocusHint.searching);
    }
  }

  void _setHint(ScanFocusHint value) {
    if (_hint == value) return;
    _hint = value;
    onHintChanged?.call(value);
  }
}
