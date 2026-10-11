import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';

/// A tour of the shared MP primitives that every task builds on: model assets,
/// typed containers, lifecycle, timestamps, and the error contract.
///
/// This file runs anywhere — even in a browser — because it never creates a
/// native task. For end-to-end inference against a real model, run one of the
/// `examples/cli/` scripts, for example:
///
/// ```sh
/// devenv shell native:build
/// dart run examples/cli/bin/vision_face_detection.dart
/// ```
void main() {
  // Model assets name exactly one source. Path, bytes, and URI variants are
  // interchangeable; URI assets may pin a SHA-256 digest for supply-chain
  // safety, and the runtime verifies it after downloading.
  final ModelAsset remote = ModelAsset.uri(
    Uri.parse('https://example.com/model.task'),
    sha256: '0' * 64,
  );
  assert(remote is ModelAssetUri && remote.sha256 == '0' * 64);

  // Invalid sources fail at construction, not at task creation.
  assert(_throwsArgumentError(() => ModelAsset.path('   ')));
  assert(
    _throwsArgumentError(
      () => ModelAsset.uri(Uri.parse('https://example.com/m.task'), sha256: 'uppercase'),
    ),
  );

  // Pixel containers are immutable and validate their samples against the
  // declared dimensions and format before copying.
  final MpImage rgb = MpImage.uint8(
    width: 2,
    height: 1,
    format: MpImageFormat.srgb,
    data: Uint8List.fromList(const <int>[30, 20, 10, 255, 0, 0]),
  );
  assert(rgb.sampleCount == 6 && rgb.byteLength == 6);
  assert(_throwsArgumentError(() => NormalizedRect(left: double.nan, top: 0, right: 1, bottom: 1)));
  assert(
    _throwsArgumentError(
      () => MpImage.uint8(width: 2, height: 1, format: MpImageFormat.srgb, data: Uint8List(5)),
    ),
  );

  // Audio is interleaved floating-point PCM; one second at 16 kHz mono is
  // exactly 16_000 samples.
  final AudioData audio = AudioData(
    channelCount: 1,
    sampleRateHz: 16_000,
    samples: Float32List(16_000),
  );
  assert(audio.duration == const Duration(seconds: 1));

  // Embedding helpers cover the common comparison: parallel vectors score 1,
  // orthogonal vectors 0.
  final Embedding first = Embedding.float(Float32List.fromList(const <double>[1, 0]), headIndex: 0);
  final Embedding second = Embedding.float(
    Float32List.fromList(const <double>[0, 1]),
    headIndex: 0,
  );
  assert(cosineSimilarity(first, first) == 1);
  assert(cosineSimilarity(first, second) == 0);

  // Every task honours the same lifecycle: close exactly once, and accept no
  // more work afterwards.
  final TaskLifecycle lifecycle = TaskLifecycle('DemoTask');
  lifecycle.ensureOpen();
  lifecycle.markClosed();
  assert(_throwsTaskClosed(lifecycle.ensureOpen));

  // Video and stream modes require strictly increasing timestamps.
  final TimestampTracker timestamps = TimestampTracker();
  timestamps.add(10);
  assert(_throwsArgumentError(() => timestamps.add(9)));
  assert(_throwsArgumentError(() => timestamps.add(-1)));
}

bool _throwsArgumentError(void Function() body) {
  try {
    body();
    return false;
  } on ArgumentError {
    return true;
  }
}

bool _throwsTaskClosed(void Function() body) {
  try {
    body();
    return false;
  } on MpTaskClosedError {
    return true;
  }
}
