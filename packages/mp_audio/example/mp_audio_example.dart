import 'dart:typed_data';

import 'package:mp_audio/mp_audio.dart';
import 'package:mp_core/mp_core.dart';

/// A tour of the audio classification surface: clip data, running modes, and
/// the unsupported-platform contract.
///
/// Each snippet is a runnable check. For classification of a real 16 kHz
/// speech clip (YAMNet) against the built native runtime, run:
///
/// ```sh
/// devenv shell native:build
/// dart run examples/cli/bin/audio_classification.dart
/// ```
Future<void> main() async {
  // Audio is interleaved floating-point PCM. A stereo frame carries two
  // interleaved samples; the channel count must divide the sample count.
  final AudioData audio = AudioData(
    channelCount: 1,
    sampleRateHz: 16_000,
    samples: Float32List(16_000),
  );
  assert(audio.duration == const Duration(seconds: 1));
  assert(
    _throwsArgumentError(
      () => AudioData(channelCount: 2, sampleRateHz: 16_000, samples: Float32List(3)),
    ),
  );
  assert(
    _throwsArgumentError(
      () => AudioData(channelCount: 1, sampleRateHz: double.nan, samples: Float32List(1)),
    ),
  );

  // Clip mode classifies whole recordings; stream mode requires strictly
  // increasing timestamps, one window per chunk.
  final AudioClassifierOptions clips = AudioClassifierOptions(
    baseOptions: BaseOptions(modelAsset: ModelAsset.path('yamnet.tflite')),
  );
  assert(clips.runningMode == AudioRunningMode.audioClips);

  // A task whose platform has no backend states that explicitly instead of
  // failing vaguely: creating one throws `MpException(MpStatus.unimplemented)`
  // naming the task.
  try {
    await AudioClassifier.create(clips, runtime: const UnsupportedAudioRuntime(MpPlatform.unknown));
    assert(false, 'Unsupported runtimes must not report success.');
  } on MpException catch (error) {
    assert(error.status == MpStatus.unimplemented);
    assert(error.task == 'AudioClassifier');
  }
}

bool _throwsArgumentError(void Function() body) {
  try {
    body();
    return false;
  } on ArgumentError {
    return true;
  }
}
