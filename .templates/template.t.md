# MP shared documentation providers

Every block in this file is a single source of truth. Consumers live in the root
`README.md`, the six package READMEs, and `docs/content/**`. Edit a provider
here, run `devenv shell docs:update`, and every consumer updates together.

Provider names must be globally unique across all `*.t.md` files in the
repository.

## Package index

The package table used by the root README and the docs overview. Generated from
`docs/data/packages.json` so a new package only has to be added in one place.

<!-- {@packageTable} -->

| Package                           | Purpose                                                                                                                        |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| [`mp_core`](packages/mp_core)     | Models, inputs, result containers, lifecycle, native assets, and web support                                                   |
| [`mp_vision`](packages/mp_vision) | The 11 vision tasks in the current MediaPipe Solutions guide, with image, video, and live-stream entry points where applicable |
| [`mp_camera`](packages/mp_camera) | Flutter camera conversion, orientation metadata, and latest-frame scheduling                                                   |
| [`mp_text`](packages/mp_text)     | Language detection, classification, embedding, proofreading, and summarization                                                 |
| [`mp_audio`](packages/mp_audio)   | Audio-clip and streaming classification                                                                                        |
| [`mp_genai`](packages/mp_genai)   | LLM inference, Android function calling, RAG, and image generation                                                             |

<!-- {/packageTable} -->

## Package index for the docs site

The same table with site-relative routes. The docs site serves each package at
`packages/<short-name>/`, not at its repository path, so the README table cannot
be reused verbatim without producing broken links.

<!-- {@packageTableDocs} -->

| Package                        | Purpose                                                                                                                        |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| [`mp_core`](packages/core)     | Models, inputs, result containers, lifecycle, native assets, and web support                                                   |
| [`mp_vision`](packages/vision) | The 11 vision tasks in the current MediaPipe Solutions guide, with image, video, and live-stream entry points where applicable |
| [`mp_camera`](packages/camera) | Flutter camera conversion, orientation metadata, and latest-frame scheduling                                                   |
| [`mp_text`](packages/text)     | Language detection, classification, embedding, proofreading, and summarization                                                 |
| [`mp_audio`](packages/audio)   | Audio-clip and streaming classification                                                                                        |
| [`mp_genai`](packages/genai)   | LLM inference, Android function calling, RAG, and image generation                                                             |

<!-- {/packageTableDocs} -->

## Task surface table

The task-family table used by the docs overview. Generated from
`docs/data/packages.json`.

<!-- {@taskSurfaceTable} -->

| Package     | Tasks                                                                                                                                                                |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `mp_vision` | Image classification and embedding, object and face detection, image and interactive segmentation, gesture recognition, and hand, pose, face, and holistic landmarks |
| `mp_text`   | Language detection, text classification, text embedding, text proofreading, text summarization                                                                       |
| `mp_audio`  | Audio classification for clips and timestamped frames                                                                                                                |
| `mp_genai`  | LLM sessions and streaming; Android function calling, RAG, and diffusion image generation                                                                            |

<!-- {/taskSurfaceTable} -->

## Independence disclaimer

Used by the root README, the docs overview, and every package README.

<!-- {@independenceNotice} -->

MP is independent software. MediaPipe is a trademark of Google LLC; this
project is not affiliated with or endorsed by Google.

<!-- {/independenceNotice} -->

## API conventions

The design contract shared by every task package. Used by the root README and
the architecture page.

<!-- {@apiConventions} -->

- Immutable, strongly typed Dart inputs and outputs.
- Explicit task ownership through idempotent `close()` methods.
- Strictly increasing timestamps for video and stream APIs.
- Latest-frame backpressure for real-time camera pipelines.
- SHA-256 verification for remotely fetched model assets.
- Injectable runtimes and small fake backends for deterministic tests.
- No package-managed model downloads.

<!-- {/apiConventions} -->

## Per-package install section

Parameterized by package name. `{{ packages[name].description }}` comes from
`docs/data/packages.json`, so the description cannot drift from the published
pubspec description.

<!-- {@packageInstall:"name"} -->

Add the package:

```yaml
dependencies:
  { { name } }: ^{{ versions.firstRelease }}
```

`{{ packages[name].description }}`

<!-- {/packageInstall} -->

## Per-package README header

The title and one-line summary every package README opens with.

<!-- {@packageHeader:"name"} -->

# {{ name }}

{{ packages[name].description }}

<!-- {/packageHeader} -->

## Per-package README pointer

The closing pointer block shared by every package README.

<!-- {@packageFooter:"name"} -->

See the [{{ name }} documentation]({{ links.docs }}{{ packages[name].docs }}/) for
the full data contract and platform notes.

<!-- {/packageFooter} -->

## Per-package task list

Parameterized by package name.

<!-- {@packageTasks:"name"} -->

- {{ packages[name].tasks }}

<!-- {/packageTasks} -->

## Version pinning table

The upstream versions this SDK binds to. Used by the models guide and the
architecture page.

<!-- {@upstreamVersions} -->

| Upstream component        | Pinned version               |
| ------------------------- | ---------------------------- |
| MediaPipe Tasks C library | `{{ versions.mediaPipe }}`   |
| `@mediapipe/tasks-vision` | `{{ versions.tasksVision }}` |
| `@mediapipe/tasks-text`   | `{{ versions.tasksText }}`   |
| `@mediapipe/tasks-audio`  | `{{ versions.tasksAudio }}`  |
| `@mediapipe/tasks-genai`  | `{{ versions.tasksGenai }}`  |

<!-- {/upstreamVersions} -->

## Model handling contract

Used by the root README's model section, the models guide, and the `mp_core`
README.

<!-- {@modelContract} -->

Models are application data, not SDK configuration. Supply one as bytes, a local
path, or an absolute HTTPS URI, and pin remote models with a SHA-256 digest:

```dart
final local = ModelAsset.path('models/gesture_recognizer.task');
final memory = ModelAsset.bytes(Uint8List.fromList(modelBytes));
final remote = ModelAsset.uri(
  Uri.parse('https://cdn.example.com/models/gesture_recognizer.task'),
  sha256: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
);
```

The SDK never chooses or downloads a model without an explicit `ModelAsset`.
Publish immutable, versioned model URLs and always provide a digest for
production clients.

<!-- {/modelContract} -->

## Lifecycle contract

Used by the root README, the quickstart, and every package README.

<!-- {@lifecycleContract} -->

Every created task implements `MpTask`. Call `close()` when inference is no
longer needed. Closing twice is safe, and invoking a closed task fails
immediately with `MpTaskClosedError`.

```dart
final detector = await ObjectDetector.create(options);
try {
  final result = await detector.detect(image);
  // Use the result.
} finally {
  await detector.close();
}
```

Long-lived tasks belong near the owning feature boundary, not inside a
per-frame callback. A task serializes its native calls, so handles are never
entered concurrently.

<!-- {/lifecycleContract} -->

## Unsupported combination contract

Used by every package README and the platform page.

<!-- {@unsupportedContract} -->

Unsupported API and platform combinations fail explicitly with
`MpException(MpStatus.unimplemented, …)` rather than silently returning empty
results. Check `MpStatus` before treating a failure as a model or input problem.

<!-- {/unsupportedContract} -->

## Support declaration

Used by the root README status section and the releases page.

<!-- {@supportDeclaration} -->

A platform is supported only when CI or a maintained device runs a real model,
resource cleanup is tested, its artifact is reproducible, and the limitation is
documented. Compilation alone is not enough.

<!-- {/supportDeclaration} -->

## Documentation links

Used wherever a README or content page needs to point back at the docs site.

<!-- {@docsLinks} -->

- [Package and API documentation]({{ links.docs }})
- [Platform support matrix]({{ links.docs }}platforms/)
- [Guides]({{ links.docs }}guides/models/)
- [Examples]({{ links.github }}/tree/main/examples)

<!-- {/docsLinks} -->
