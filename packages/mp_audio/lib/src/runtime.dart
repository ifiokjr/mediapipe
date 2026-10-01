import 'package:mp_core/mp_core.dart';

import 'audio_classifier.dart';
import 'runtime_stub.dart'
    if (dart.library.io) 'runtime_native.dart'
    if (dart.library.js_interop) 'runtime_web.dart'
    as platform;

/// A platform adapter capable of creating MediaPipe audio task backends.
abstract interface class AudioRuntime {
  /// Creates an audio classifier backend.
  Future<AudioClassifierBackend> createAudioClassifier(AudioClassifierOptions options);
}

/// The adapter selected for the active platform.
AudioRuntime get defaultAudioRuntime => platform.createAudioRuntime();

/// An adapter used when the current build has no linked MediaPipe runtime.
final class UnsupportedAudioRuntime implements AudioRuntime {
  /// Creates an unsupported adapter for [platform].
  const UnsupportedAudioRuntime(this.platform);

  /// The platform for which no implementation was linked.
  final MpPlatform platform;

  @override
  Future<AudioClassifierBackend> createAudioClassifier(AudioClassifierOptions options) async =>
      throw MpException(
        MpStatus.unimplemented,
        'No AudioClassifier backend is linked for ${platform.name}.',
        task: 'AudioClassifier',
      );
}
