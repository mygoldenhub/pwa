import 'dart:ui';

import 'package:pwa/utils/camera_focus_types.dart';

import 'camera_focus_stub.dart'
    if (dart.library.html) 'camera_focus_web.dart' as impl;

export 'package:pwa/utils/camera_focus_types.dart';

/// Probe / enable continuous autofocus when the browser camera supports it.
Future<WebCameraCapabilities> enableContinuousCameraFocus() =>
    impl.enableContinuousCameraFocus();

/// Manual focus at a normalized point (0..1).
Future<bool> focusCameraAt(Offset normalizedPoint) =>
    impl.focusCameraAt(normalizedPoint);

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

/// Un-mirror the live &lt;video&gt; with CSS.
/// Flutter Transform/ClipRect freeze HtmlElementView in production CanvasKit.
void applyWebVideoPreviewStyle() => impl.applyWebVideoPreviewStyle();
