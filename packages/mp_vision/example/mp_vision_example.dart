import 'package:mp_core/mp_core.dart';
import 'package:mp_vision/mp_vision.dart';

/// A tour of the vision task surface: options, running modes, results, and
/// interactive prompts.
///
/// Each snippet is a runnable check. For end-to-end inference against real
/// MediaPipe models — face detection over a real photograph, or hand landmarks
/// with world coordinates — run the CLI demos:
///
/// ```sh
/// devenv shell native:build
/// dart run examples/cli/bin/vision_face_detection.dart
/// dart run examples/cli/bin/vision_hand_landmarks.dart
/// ```
void main() {
  // Options validate when constructed, so a bad task never reaches a runtime.
  final FaceDetectorOptions detector = FaceDetectorOptions(
    baseOptions: BaseOptions(modelAsset: ModelAsset.path('face_detector.task')),
  );
  assert(detector.minDetectionConfidence == 0.5);
  assert(
    _throwsArgumentError(
      () => HandLandmarkerOptions(
        baseOptions: BaseOptions(modelAsset: ModelAsset.path('hands.task')),
        numHands: 0,
      ),
    ),
  );

  // Input transforms accept quarter turns only; any other angle fails early.
  final ImageProcessingOptions rotate = ImageProcessingOptions(rotationDegrees: 270);
  assert(rotate.rotationDegrees == 270);
  assert(_throwsArgumentError(() => ImageProcessingOptions(rotationDegrees: 45)));

  // Interactive segmentation prompts are immutable and validated: an empty
  // scribble or stroke set is rejected up front.
  final InteractivePrompt prompt = InteractivePrompt.strokes(<PromptStroke>[
    PromptStroke(brushMode: BrushMode.positive, points: <PromptPoint>[PromptPoint(0.5, 0.5)]),
  ]);
  assert(prompt is StrokePrompt);
  assert(_throwsArgumentError(() => InteractivePrompt.scribble(const <PromptPoint>[])));
  assert(_throwsArgumentError(() => PromptPoint(1.2, 0.5)));

  // Results are immutable value types with structural equality.
  final PoseLandmarkerResult result = PoseLandmarkerResult(
    landmarks: const <Iterable<NormalizedLandmark>>[
      <NormalizedLandmark>[NormalizedLandmark(x: 0.5, y: 0.5, z: 0)],
    ],
    worldLandmarks: const <Iterable<Landmark>>[
      <Landmark>[Landmark(x: 0, y: 0, z: 0)],
    ],
  );
  assert(result.landmarks.single.single.x == 0.5);
  assert(
    result ==
        PoseLandmarkerResult(
          landmarks: const <Iterable<NormalizedLandmark>>[
            <NormalizedLandmark>[NormalizedLandmark(x: 0.5, y: 0.5, z: 0)],
          ],
          worldLandmarks: const <Iterable<Landmark>>[
            <Landmark>[Landmark(x: 0, y: 0, z: 0)],
          ],
        ),
  );

  // Note: creating a task against `defaultVisionRuntime` fails explicitly with
  // `MpException` when the current platform provides no backend — it never
  // silently returns empty results.
}

bool _throwsArgumentError(void Function() body) {
  try {
    body();
    return false;
  } on ArgumentError {
    return true;
  }
}
