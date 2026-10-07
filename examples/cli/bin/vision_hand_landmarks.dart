// Run with: dart run examples/cli/bin/vision_hand_landmarks.dart
//
// Detects hand landmarks in a photograph with the MediaPipe hand landmarker
// task bundle, printing per-hand handedness, landmark counts, and a few sample
// normalized coordinates. The model and image are downloaded once, cached, and
// verified against their pinned SHA-256 digests before inference.
//
// The native runtime is resolved by the mp_core native asset hook from the
// `.mp-sdk` directory built by `native:build`; the browser adapter needs no
// native runtime.

import 'dart:io';
import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';
import 'package:mp_examples/mp_examples.dart';
import 'package:mp_vision/mp_vision.dart';

Future<void> main() => runExample('vision_hand_landmarks', () async {
  final MpAssetCache cache = MpAssetCache.defaults();
  final HandLandmarker landmarker = await HandLandmarker.create(
    HandLandmarkerOptions(
      baseOptions: BaseOptions(modelAsset: await cache.model(MpExampleModels.handLandmarker)),
      numHands: 2,
      minHandDetectionConfidence: 0.4,
    ),
  );

  try {
    final Uint8List imageBytes = await cache.bytes(MpExampleInputs.catsAndDogs);
    final MpImage image = mpImageFromBytes(imageBytes);
    stdout.writeln('Input: ${image.width}x${image.height} ${image.format.name}');

    final HandLandmarkerResult result = await landmarker.detect(image);
    stdout.writeln('Hands detected: ${result.landmarks.length}');
    for (int hand = 0; hand < result.landmarks.length; hand += 1) {
      final List<Category> handedness = result.handedness[hand];
      final String label = handedness.isEmpty
          ? '?'
          : handedness.first.displayName ?? handedness.first.categoryName ?? '?';
      final List<NormalizedLandmark> landmarks = result.landmarks[hand];
      final NormalizedLandmark wrist = landmarks.first;
      final NormalizedLandmark middleTip = landmarks[9];
      stdout.writeln(
        '  hand $hand: $label (${handedness.isEmpty ? 0 : handedness.first.score.toStringAsFixed(2)}) '
        '${landmarks.length} landmarks',
      );
      stdout.writeln(
        '    wrist=(${wrist.x.toStringAsFixed(3)}, ${wrist.y.toStringAsFixed(3)}) '
        'middleTip=(${middleTip.x.toStringAsFixed(3)}, ${middleTip.y.toStringAsFixed(3)})',
      );
      stdout.writeln(
        '    world wrist=(${result.worldLandmarks[hand].first.x.toStringAsFixed(3)} m, '
        '${result.worldLandmarks[hand].first.y.toStringAsFixed(3)} m)',
      );
    }
  } finally {
    await landmarker.close();
  }
});
