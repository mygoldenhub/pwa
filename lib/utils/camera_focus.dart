import 'dart:ui';

import 'package:pwa/utils/camera_focus_types.dart';

import 'camera_focus_stub.dart'
    if (dart.library.html) 'camera_focus_web.dart' as impl;

export 'package:pwa/utils/camera_focus_types.dart';

/// Probe / enable continuous autofocus when the browser camera supports it.
Future<WebCameraCapabilities> enableContinuousCameraFocus() =>
    impl.enableContinuousCameraFocus();

/// Manual focus (or zoom fallback) at a normalized point (0..1).
Future<bool> focusCameraAt(Offset normalizedPoint) =>
    impl.focusCameraAt(normalizedPoint);

/// Set hardware zoom when supported. [normalized] is 0..1.
Future<bool> setWebCameraZoom(double normalized) =>
    impl.setWebCameraZoom(normalized);

/// Set flashlight when the browser camera supports torch constraints.
Future<bool> setWebTorch(bool enabled) => impl.setWebTorch(enabled);

Future<bool> webTorchSupported() => impl.webTorchSupported();

/// True when the web camera preview is CSS-mirrored (front / desktop cameras).
bool webPreviewIsMirrored() => impl.webPreviewIsMirrored();

bool webIsAppleMobile() => impl.webIsAppleMobile();

WebCameraCapabilities probeWebCameraCapabilities() =>
    impl.probeWebCameraCapabilities();

/// Stop leftover getUserMedia tracks so the camera can start again.
Future<void> releaseWebCameraTracks() => impl.releaseWebCameraTracks();
