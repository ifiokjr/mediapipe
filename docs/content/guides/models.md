---
title: Models and assets
description: Load task bundles predictably and protect the model supply chain.
---

## Choose a task-compatible model

MediaPipe Task APIs expect task bundles or compatible TFLite models with the metadata required by that task. A model that runs in raw LiteRT is not automatically a MediaPipe Task model. Record the model source, license, upstream version, expected input, and digest alongside application code.

## Prefer immutable releases

Do not point production clients at a mutable “latest” URL. Publish versioned model objects and verify their SHA-256 digest. Browser `ModelAsset.uri` values can supply that digest directly; native apps should perform the same check while downloading to application storage.

```dart
final asset = ModelAsset.uri(
  Uri.parse('https://cdn.example.com/models/language_detector/1/model.tflite'),
  sha256: '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
);
```

## Bundled assets

Flutter assets are not filesystem paths. Copy the bytes from the asset bundle and use `ModelAsset.bytes`, or write them to a versioned file and use `ModelAsset.path`. For large GenAI weights, use platform storage and plan for resumable downloads, available disk checks, and removal of obsolete versions.

## Secrets

An application binary cannot keep a long-lived download secret. Use public model artifacts or a server-issued short-lived download URL. Never log signed URLs or authorization headers.

## Licensing

The SDK does not redistribute task models. Applications are responsible for model licenses and notices. Keep the selected model’s license visible in product and distribution records.
