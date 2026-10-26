import 'dart:ui';

import 'package:flutter/painting.dart' show Alignment, BoxFit, FittedSizes, applyBoxFit;
import 'package:meta/meta.dart';
import 'package:mp_core/mp_core.dart';

import 'camera_frame.dart';
import 'rotation_math.dart';

/// Maps inference coordinates onto the camera preview widget.
///
/// MediaPipe reports normalized landmarks and pixel bounding boxes relative to
/// the frame *after* the rotation in [ImageProcessingOptions] is applied —
/// the upright image the preview shows. This transform folds in that upright
/// size, a mirrored front-camera preview, and the [BoxFit] used to place the
/// preview inside the widget ([BoxFit.cover] crops, [BoxFit.contain]
/// letterboxes), so a painter can place results without re-deriving any of
/// the geometry.
///
/// ```dart
/// final transform = CameraOverlayTransform.forFrame(frame, viewSize: size);
/// for (final landmark in result.landmarks.first) {
///   canvas.drawCircle(transform.mapLandmark(landmark), 4, paint);
/// }
/// ```
@immutable
final class CameraOverlayTransform {
  /// Creates a transform for a frame of [imageSize] pixels rotated by
  /// [rotationDegrees] before inference and shown in a widget of [viewSize].
  CameraOverlayTransform({
    required Size imageSize,
    required int rotationDegrees,
    required this.viewSize,
    this.mirrored = false,
    this.fit = BoxFit.cover,
  }) : uprightSize = _uprightSize(imageSize, rotationDegrees) {
    if (viewSize.width <= 0 || viewSize.height <= 0) {
      throw ArgumentError.value(viewSize, 'viewSize', 'must have positive dimensions');
    }

    final FittedSizes fitted = applyBoxFit(fit, uprightSize, viewSize);

    sourceRect = Alignment.center.inscribe(fitted.source, Offset.zero & uprightSize);
    destinationRect = Alignment.center.inscribe(fitted.destination, Offset.zero & viewSize);
  }

  /// Builds the transform for [frame] using its rotation and mirroring flags.
  factory CameraOverlayTransform.forFrame(
    MpCameraFrame frame, {
    required Size viewSize,
    BoxFit fit = BoxFit.cover,
  }) => CameraOverlayTransform(
    imageSize: Size(frame.image.width.toDouble(), frame.image.height.toDouble()),
    rotationDegrees: frame.processingOptions.rotationDegrees,
    viewSize: viewSize,
    mirrored: frame.mirroredPreview,
    fit: fit,
  );

  /// Size of the image after the inference rotation, in pixels.
  final Size uprightSize;

  /// Size of the widget the preview is painted into.
  final Size viewSize;

  /// Whether the preview mirrors the sensor image horizontally.
  final bool mirrored;

  /// How the upright image is fitted into [viewSize].
  final BoxFit fit;

  /// The part of the upright image that is visible, in image pixels.
  late final Rect sourceRect;

  /// Where that visible part lands in the widget, in logical pixels.
  late final Rect destinationRect;

  /// Horizontal scale from image pixels to widget pixels.
  double get scaleX => destinationRect.width / sourceRect.width;

  /// Vertical scale from image pixels to widget pixels.
  double get scaleY => destinationRect.height / sourceRect.height;

  /// Widget position of a point given in normalized upright-image coordinates.
  Offset mapNormalized(double x, double y) =>
      mapPixel(x * uprightSize.width, y * uprightSize.height);

  /// Widget position of [landmark].
  Offset mapLandmark(NormalizedLandmark landmark) => mapNormalized(landmark.x, landmark.y);

  /// Widget position of a point given in upright-image pixels.
  Offset mapPixel(double x, double y) {
    final double sensorX = mirrored ? uprightSize.width - x : x;

    return Offset(
      destinationRect.left + (sensorX - sourceRect.left) * scaleX,
      destinationRect.top + (y - sourceRect.top) * scaleY,
    );
  }

  /// Widget rectangle covering a normalized region of interest.
  Rect mapNormalizedRect(NormalizedRect rect) =>
      Rect.fromPoints(mapNormalized(rect.left, rect.top), mapNormalized(rect.right, rect.bottom));

  /// Widget rectangle covering a pixel [BoundingBox] from a detection.
  Rect mapBoundingBox(BoundingBox box) => Rect.fromPoints(
    mapPixel(box.left.toDouble(), box.top.toDouble()),
    mapPixel((box.left + box.width).toDouble(), (box.top + box.height).toDouble()),
  );

  static Size _uprightSize(Size imageSize, int rotationDegrees) {
    if (imageSize.width <= 0 || imageSize.height <= 0) {
      throw ArgumentError.value(imageSize, 'imageSize', 'must have positive dimensions');
    }

    if (rotationDegrees % 90 != 0) {
      throw ArgumentError.value(rotationDegrees, 'rotationDegrees', 'must be a multiple of 90');
    }

    final int quarterTurns = normalizeRotationDegrees(rotationDegrees) ~/ 90;

    return quarterTurns.isOdd ? Size(imageSize.height, imageSize.width) : imageSize;
  }
}
