import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';

void main() {
  final AudioData audio = AudioData(
    channelCount: 1,
    sampleRateHz: 16_000,
    samples: Float32List(16_000),
  );
  assert(audio.duration == const Duration(seconds: 1), 'Expected one second of audio.');
}
