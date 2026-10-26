# mp_benchmarks

Microbenchmarks for the MP SDK's per-frame hot paths and the data source for the
performance regression gate that runs on every pull request.

## Run locally

```sh
devenv shell bench:run
devenv shell bench:run -- --filter pixel_conversion --rounds 3
devenv shell bench:run -- --json /tmp/head.json
```

Or directly: `dart run benchmarks/bin/run.dart --help`.

## What is measured

| Suite                | Hot path                                                               |
| -------------------- | ---------------------------------------------------------------------- |
| `pixel_conversion`   | BGRA8888, NV21, and YUV420 (planar and semi-planar) to packed RGB(A)   |
| `image_construction` | Copying versus adopting a 720p buffer into an `MpImage`                |
| `isolate_transfer`   | Sending a 720p frame to a native-task worker isolate, one way and back |
| `result_containers`  | Landmark list materialization and embedding cosine similarity          |

Every benchmark has a stable `suite/case/variant` name. Keep names unchanged
unless the measured operation changes; the gate treats a vanished name as a
failure so a regression cannot hide behind a rename.

## The gate

CI runs this package twice on the same runner — once at the pull request's base
commit and once at its head — and `tool/compare_benchmarks.dart` fails the job
when the fastest measured run (`min`, the default metric) regresses by more
than the configured threshold. Running both
commits on one machine cancels out runner-to-runner speed differences, so the
comparison is relative rather than against a stored absolute baseline.

Add a benchmark whenever you add or change a per-frame code path: construct
inputs in `setUp`, keep `run` to the operation under test, and prefer the
`tiny` frame size in tests.
