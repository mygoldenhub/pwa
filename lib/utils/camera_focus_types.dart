/// What the active web camera actually supports.
class WebCameraCapabilities {
  const WebCameraCapabilities({
    required this.supportsFocus,
    required this.supportsZoom,
    required this.supportsTorch,
    required this.zoomMin,
    required this.zoomMax,
  });

  const WebCameraCapabilities.unsupported()
      : supportsFocus = false,
        supportsZoom = false,
        supportsTorch = false,
        zoomMin = 1,
        zoomMax = 1;

  final bool supportsFocus;
  final bool supportsZoom;
  final bool supportsTorch;
  final double zoomMin;
  final double zoomMax;

  bool get hasManualControls => supportsFocus || supportsZoom;
}
