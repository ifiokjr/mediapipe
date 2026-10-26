---
mp_core: feat
mp_camera: fix
---

# Frame pacing and live scheduling telemetry

- `mp_core`: `LatestFrameScheduler` moves here from `mp_camera` so pure Dart
  pipelines can use it, and gains a `maxQueueAge` policy that discards a frame
  which waited through a long inference stall instead of running it late, a
  `stats` snapshot with counters, `processedPerSecond`, and rolling p50/p95
  queue-wait and processing times, and a `dart:developer` timeline task around
  every processed frame for DevTools.
- `mp_core`: `FramePacer` admits one frame per interval by camera timestamp
  before any pixel conversion runs, so a skipped frame costs nothing;
  `FramePacer.targetFps` derives the interval from a target rate.
- `mp_core`: `LatencyWindow` is the bounded rolling window with nearest-rank
  percentiles behind the scheduler statistics, public for timing other stages.
- `mp_camera`: re-exports `LatestFrameScheduler`, `LatestFrameFailure`, and
  `LatestFrameStats` from `mp_core`; existing imports keep working.
