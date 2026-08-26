import 'dart:ui';

/// What the web scanner is doing right now.
///
/// Surfaced behind a long press on the scanner hint so a scanning problem can
/// be diagnosed on the device it happens on, which is usually not one we can
/// attach a debugger to.
class WebScanDiagnostics {
  const WebScanDiagnostics({
    required this.backend,
    required this.videoSize,
    required this.cropSize,
    required this.focusScore,
    required this.attempts,
    required this.decodes,
    required this.lastError,
  });

  const WebScanDiagnostics.unavailable()
      : backend = 'not running',
        videoSize = Size.zero,
        cropSize = Size.zero,
        focusScore = null,
        attempts = 0,
        decodes = 0,
        lastError = null;

  /// Which decoder(s) the cropped poller can currently use.
  final String backend;

  /// Resolution of the camera stream.
  final Size videoSize;

  /// Size of the decoded crop, in camera pixels.
  final Size cropSize;

  /// Sharpness of the framed region; roughly 14+ means in focus.
  final double? focusScore;

  /// Decode attempts and successes since the camera started.
  final int attempts;
  final int decodes;

  final String? lastError;

  List<String> get lines => <String>[
        'decoder: $backend',
        'camera: ${_size(videoSize)}   crop: ${_size(cropSize)}',
        'focus: ${focusScore?.toStringAsFixed(1) ?? '-'}'
            '   tries: $attempts   hits: $decodes',
        if (lastError != null) 'error: $lastError',
      ];

  static String _size(Size size) {
    if (size == Size.zero) return '-';
    return '${size.width.round()}x${size.height.round()}';
  }
}
