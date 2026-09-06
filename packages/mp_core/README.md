# mp_core

Shared types, model loading, lifecycle, and runtime primitives for the MP
MediaPipe Tasks SDK.

Use `mp_core` directly when building a custom task adapter, or transitively
through `mp_vision`, `mp_text`, `mp_audio`, or `mp_genai`.

## What it provides

- Immutable image, audio, landmark, classification, detection, embedding, and
  segmentation containers.
- Models loaded from bytes, local paths, or absolute URIs.
- Optional SHA-256 verification for remotely loaded models.
- CPU, GPU, Edge TPU NNAPI, and LiteRT delegate configuration.
- Task lifecycle, status errors, timestamp validation, and injectable runtimes.
- Generated FFI bindings for the public MediaPipe Tasks C headers.
- Shared browser module and model-asset helpers.

## Model assets

```dart
import 'dart:typed_data';

import 'package:mp_core/mp_core.dart';

final local = ModelAsset.path('models/gesture_recognizer.task');
final memory = ModelAsset.bytes(Uint8List.fromList(modelBytes));
final remote = ModelAsset.uri(
  Uri.parse('https://cdn.example.com/models/gesture_recognizer.task'),
  sha256: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
);

final options = BaseOptions(modelAsset: local, delegate: MpDelegate.cpu);
```

The SDK never chooses or downloads a model without an explicit `ModelAsset`.
For security-sensitive applications, publish immutable model URLs and always
provide a digest.

## Ownership

Every created task implements `MpTask`. Call `close()` when inference is no
longer needed; closing twice is safe, while invoking a closed task fails
immediately.

See the [MP documentation](https://ifiokjr.github.io/mediapipe/packages/core/)
for the full data contract and platform notes.

MP is independent software and is not affiliated with or endorsed by Google.
