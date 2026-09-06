# mp_vision

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

See the [vision guide](https://ifiokjr.github.io/mediapipe/packages/vision/) and
[live-stream guide](https://ifiokjr.github.io/mediapipe/guides/live-streams/).

MP is independent software and is not affiliated with or endorsed by Google.
