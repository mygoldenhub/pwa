import 'dart:ui';

import 'package:pwa/utils/camera_focus_types.dart';

export 'package:pwa/utils/camera_focus_types.dart';

Future<WebCameraCapabilities> enableContinuousCameraFocus() async {
  return const WebCameraCapabilities.unsupported();
}

Future<bool> focusCameraAt(Offset normalizedPoint) async => false;

Future<bool> setWebCameraZoom(double normalized) async => false;

Future<bool> setWebTorch(bool enabled) async => false;

Future<bool> webTorchSupported() async => false;

WebCameraCapabilities probeWebCameraCapabilities() {
  return const WebCameraCapabilities.unsupported();
}
