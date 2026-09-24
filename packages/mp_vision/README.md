<!-- {=packageHeader:"mp_vision"} -->

# mp_vision

Cross-platform MediaPipe vision tasks for Dart and Flutter.

<!-- {/packageHeader} -->

The 11 vision tasks listed in the current MediaPipe Solutions guide.

## Tasks

- Face detection and face landmarking
- Gesture recognition and hand landmarking
- Holistic and pose landmarking
- Image classification and embedding
- Image and interactive segmentation
- Object detection

Tasks support still-image, decoded-video, and live-stream modes where the
upstream runtime exposes them. Results are immutable and masks own their pixel
buffers.

## Install

<!-- {=packageInstall:"mp_vision"} -->

Add the package:

```yaml
dependencies:
  { { name } }: ^0.1.0
```

`Cross-platform MediaPipe vision tasks for Dart and Flutter.`

<!-- {/packageInstall} -->

## Usage

```dart
import 'package:mp_core/mp_core.dart';
import 'package:mp_vision/mp_vision.dart';

final landmarker = await FaceLandmarker.create(
  FaceLandmarkerOptions(
    baseOptions: BaseOptions(
      modelAsset: ModelAsset.path('models/face_landmarker.task'),
    ),
    outputFaceBlendshapes: true,
  ),
);

try {
  final result = await landmarker.detect(image);
  print(result.faceLandmarks.length);
} finally {
  await landmarker.close();
}
```

For Flutter camera streams, add `mp_camera`. It converts BGRA8888, NV21, and
stride-aware YUV420 frames, resolves image rotation, and keeps at most the
newest waiting frame so inference does not accumulate stale camera buffers.

A runnable example lives in [`example/`](example/). It detects faces in a
bundled image and prints the landmarks.

## Failure contract

<!-- {=unsupportedContract} -->

Unsupported API and platform combinations fail explicitly with
`MpException(MpStatus.unimplemented, …)` rather than silently returning empty
results. Check `MpStatus` before treating a failure as a model or input problem.

<!-- {/unsupportedContract} -->

See the [vision guide]({{ links.docs }}packages/vision/) and
[live-stream guide]({{ links.docs }}guides/live-streams/).

<!-- {=packageFooter:"mp_vision"} -->

See the [mp_vision documentation](https://ifiokjr.github.io/mediapipe/packages/vision/) for
the full data contract and platform notes.

<!-- {/packageFooter} -->

<!-- {=independenceNotice} -->

MP is independent software. MediaPipe is a trademark of Google LLC; this
project is not affiliated with or endorsed by Google.

<!-- {/independenceNotice} -->
