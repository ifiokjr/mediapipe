import 'package:mp_core/mp_core.dart';

import '../harness.dart';

/// Per-frame scheduling overhead: pacing, submit/drain, and live statistics.
///
/// These run once per camera callback, so they must stay negligible next to
/// conversion and inference.
BenchmarkSuite frameSchedulingSuite() {
  late LatestFrameScheduler<int> scheduler;
  late LatestFrameScheduler<int> warmScheduler;
  late FramePacer pacer;
  late LatencyWindow window;

  return BenchmarkSuite(
    name: 'frame_scheduling',
    benchmarks: <Benchmark>[
      Benchmark(
        // 1 000 frames per iteration (~3 ms) rather than 100 (~0.3 ms):
        // sub-millisecond event-loop timings are dominated by scheduler
        // jitter on shared CI runners, which drowns the real signal.
        name: 'frame_scheduling/scheduler_submit_await/1000',
        setUp: () => scheduler = LatestFrameScheduler<int>((int _) async {}),
        run: () async {
          for (int frame = 0; frame < 1000; frame += 1) {
            scheduler.submit(frame);
            await scheduler.idle;
          }

          return scheduler.processedCount;
        },
        tearDown: () => scheduler.close(),
      ),
      Benchmark(
        name: 'frame_scheduling/scheduler_stats/120',
        setUp: () async {
          warmScheduler = LatestFrameScheduler<int>((int _) async {});

          for (int frame = 0; frame < 120; frame += 1) {
            warmScheduler.submit(frame);
            await warmScheduler.idle;
          }
        },
        run: () => warmScheduler.stats,
        tearDown: () => warmScheduler.close(),
      ),
      Benchmark(
        name: 'frame_scheduling/pacer_admit/10000',
        setUp: () => pacer = FramePacer.targetFps(15),
        run: () {
          pacer.reset();

          for (int frame = 0; frame < 10000; frame += 1) {
            pacer.admit(frame * 33);
          }

          return pacer.admittedCount;
        },
      ),
      Benchmark(
        name: 'frame_scheduling/latency_window_add_p95/120',
        setUp: () => window = LatencyWindow(),
        run: () {
          for (int sample = 0; sample < 120; sample += 1) {
            window.add(Duration(microseconds: (sample * 7919) % 50000));
          }

          return window.p95;
        },
      ),
    ],
  );
}
