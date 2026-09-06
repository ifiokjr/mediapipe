---
title: mp_text
description: Text task constructors, results, streaming APIs, and backend availability.
---

## API

| Task               | Methods                           | Result types                                    |
| ------------------ | --------------------------------- | ----------------------------------------------- |
| `LanguageDetector` | `detect(text)`                    | `LanguageDetectorResult`                        |
| `TextClassifier`   | `classify(text)`                  | `ClassificationResult`                          |
| `TextEmbedder`     | `embed(text, formatContext: ...)` | `EmbeddingResult`                               |
| `TextProofreader`  | `proofread`, `proofreadStreaming` | `TextProofreaderResult`, `TextProofreaderChunk` |
| `TextSummarizer`   | `summarize`, `summarizeStreaming` | `TextSummarizerResult`, `TextSummarizerChunk`   |

Create each task with `TaskName.create(TaskNameOptions(...))` and release it with `close()`. All options contain `BaseOptions`; classifier and embedder options also contain their shared `mp_core` option groups.

## LanguageDetector

Returns ordered BCP-47 language predictions and probabilities. A real-browser integration test runs the official language detector model and verifies the model digest path.

## TextClassifier

Returns classification heads with stable category indices, scores, labels, and display names. Shared `ClassifierOptions` provide allowlists, denylists, maximum results, thresholds, and locale selection.

## TextEmbedder

Returns floating-point or quantized embedding heads. Enable L2 normalization when cosine similarity is the intended comparison and keep the choice consistent between indexed and query embeddings.

## TextProofreader

`proofread` returns corrected text plus an ordered list of unchanged, inserted, and deleted segments. `proofreadStreaming` emits text chunks and includes the final correction list on the completed chunk.

```dart
final proofreader = await TextProofreader.create(
  TextProofreaderOptions(
    baseOptions: BaseOptions(
      modelAsset: ModelAsset.path('models/proofreader.litertlm'),
    ),
    maxTokens: 2048,
  ),
);
```

## TextSummarizer

`TextSummarizerMode.tldr` requests a short paragraph. `TextSummarizerMode.keyPoints` requests a key-point list and is the default. Both blocking and streaming methods are exposed.

## Backend availability

| Task                | Web             | C runtime       | Android                   | iOS                       |
| ------------------- | --------------- | --------------- | ------------------------- | ------------------------- |
| Language detection  | Implemented     | Implemented     | C packaging in validation | Planned                   |
| Text classification | Implemented     | Implemented     | C packaging in validation | Planned                   |
| Text embedding      | Implemented     | Implemented     | C packaging in validation | Planned                   |
| Text proofreading   | No upstream API | No upstream API | Native constructor tested | Native constructor tested |
| Text summarization  | No upstream API | No upstream API | Native constructor tested | Native constructor tested |

Unsupported combinations fail during task creation with `MpStatus.unimplemented`.

Task instances own native or JavaScript resources. Reuse them across calls and close them at the feature lifecycle boundary.

Only one proofreader or summarizer operation may be active on a task instance.
Cancelling a Dart subscription stops delivery to that subscriber; it does not
cancel generation in the platform SDK. Wait for the native operation to finish
before starting another call or closing the task.
