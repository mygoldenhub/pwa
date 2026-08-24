/// What the active web camera actually supports.
class WebCameraCapabilities {
  const WebCameraCapabilities({
    required this.supportsFocus,
    required this.supportsTorch,
  });

  const WebCameraCapabilities.unsupported()
      : supportsFocus = false,
        supportsTorch = false;

  final bool supportsFocus;
  final bool supportsTorch;

  bool get hasManualControls => supportsFocus;
}
