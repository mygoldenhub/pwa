/// What the active web camera actually supports.
class WebCameraCapabilities {
  const WebCameraCapabilities({
    required this.supportsFocus,
    required this.supportsTorch,
    this.supportsFocusDistance = false,
  });

  const WebCameraCapabilities.unsupported()
      : supportsFocus = false,
        supportsTorch = false,
        supportsFocusDistance = false;

  final bool supportsFocus;
  final bool supportsTorch;

  /// Whether the lens can be driven to an explicit distance, which is what
  /// makes a focus sweep possible.
  final bool supportsFocusDistance;

  bool get hasManualControls => supportsFocus;
}

/// The range accepted by the `focusDistance` constraint.
///
/// The unit is whatever the camera reports: Chrome on Android uses metres,
/// some drivers use a normalized 0..1 scale where small means near.
class WebFocusRange {
  const WebFocusRange({
    required this.min,
    required this.max,
    required this.step,
  });

  final double min;
  final double max;
  final double step;

  bool get isUsable => max > min;

  /// Lens positions to try during a focus sweep, nearest first.
  ///
  /// Mixes absolute close-range distances (a barcode is held at roughly
  /// 5-40 cm) with points spread over the reported range, so the sweep still
  /// covers the near end on cameras that do not report metres.
  List<double> sweepPositions({int limit = 8}) {
    if (!isUsable) return const <double>[];

    final span = max - min;
    final wanted = <double>[
      min,
      0.05,
      0.08,
      0.12,
      0.20,
      0.35,
      min + span * 0.05,
      min + span * 0.12,
      min + span * 0.25,
      min + span * 0.45,
    ];

    final seen = <double>[];
    for (final value in wanted) {
      if (value < min || value > max) continue;
      final snapped = _snap(value);
      if (seen.any((v) => (v - snapped).abs() < _tolerance)) continue;
      seen.add(snapped);
    }
    seen.sort();
    return seen.length <= limit ? seen : seen.sublist(0, limit);
  }

  double get _tolerance => step > 0 ? step / 2 : (max - min) / 200;

  double _snap(double value) {
    if (step <= 0) return value;
    final steps = ((value - min) / step).round();
    return (min + steps * step).clamp(min, max);
  }
}
