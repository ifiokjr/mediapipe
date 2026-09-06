---
title: Quickstart
description: Create a task, run inference, and close it deterministically.
---

## 1. Add a task package

Choose the narrowest package that contains your task. Its dependency on `mp_core` supplies the shared model and data types.

```yaml
dependencies:
  mp_vision: ^0.1.0
```

During pre-release development, use a Git dependency or a local path until the first packages are published.

## 2. Provide a model

Models are application data, not SDK configuration. A model can come from a file, bytes, or a URL. For production browser builds, pin remote bytes with a digest.

```dart
final model = ModelAsset.uri(
  Uri.parse('https://example.com/models/efficientdet.tflite'),
  sha256: 'the-expected-lowercase-sha256-digest',
);
```

Native applications should normally download a versioned model to application storage, verify it, and pass its file path. Do not put private model URLs or tokens in client source.

## 3. Create and use the task

```dart
import 'package:mp_core/mp_core.dart';
import 'package:mp_vision/mp_vision.dart';

Future<List<Detection>> detect(MpImage image) async {
  final detector = await ObjectDetector.create(
    ObjectDetectorOptions(
      baseOptions: BaseOptions(modelAsset: model),
    ),
  );
  try {
    final result = await detector.detect(image);
    return result.detections;
  } finally {
    await detector.close();
  }
}
```

Create long-lived task instances near the owning feature boundary rather than once per frame. A task serializes native calls so handles are never entered concurrently.

## 4. Select the execution mode

- `image` accepts independent images.
- `video` accepts monotonically increasing timestamps.
- `liveStream` produces ordered asynchronous results where the platform exposes safe callback ownership. See [live streams](guides/live-streams) for adapter behavior.

## 5. Test without a model

Every public task accepts an injectable runtime. Tests can substitute an implementation and verify application behavior without a network, GPU, or native SDK.

Continue with the package pages or inspect the [examples]({{links.github}}/tree/main/packages).
