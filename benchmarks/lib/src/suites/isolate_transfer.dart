import 'package:mp_core/mp_core.dart';
import 'package:mp_core/native.dart' show NativeTaskIsolate, NativeTaskWorkerHandler;

import '../harness.dart';
import '../synthetic.dart';

/// Moving a frame onto a native-task worker isolate and getting results back.
///
/// Every native vision call pays the one-way send; tasks that return images,
/// such as segmentation masks, pay the round trip.
BenchmarkSuite isolateTransferSuite({FrameSize size = hd720}) {
  final String label = sizeLabel(size);
  late MpImage image;
  NativeTaskIsolate? byteLengthWorker;
  NativeTaskIsolate? echoWorker;

  return BenchmarkSuite(
    name: 'isolate_transfer',
    benchmarks: <Benchmark>[
      Benchmark(
        name: 'isolate_transfer/send_image/${label}_srgb',
        setUp: () async {
          image = _srgbImage(size);
          byteLengthWorker = await NativeTaskIsolate.spawn(
            factory: byteLengthWorkerFactory,
            initialMessage: null,
            debugName: 'mp_benchmarks.byte_length',
          );
        },
        run: () => byteLengthWorker!.request<int>(image),
        tearDown: () => byteLengthWorker!.dispose(),
      ),
      Benchmark(
        // Five round trips per iteration (~5 ms): a single 720p round trip
        // can swing by tens of percent on a shared runner, which is jitter
        // in the event loop rather than in the transfer itself.
        name: 'isolate_transfer/roundtrip_image/${label}_srgb_x5',
        setUp: () async {
          image = _srgbImage(size);
          echoWorker = await NativeTaskIsolate.spawn(
            factory: echoWorkerFactory,
            initialMessage: null,
            debugName: 'mp_benchmarks.echo',
          );
        },
        run: () async {
          MpImage latest = image;

          for (int trip = 0; trip < 5; trip += 1) {
            latest = await echoWorker!.request<MpImage>(latest);
          }

          return latest;
        },
        tearDown: () => echoWorker!.dispose(),
      ),
    ],
  );
}

MpImage _srgbImage(FrameSize size) => MpImageUint8.adopt(
  width: size.width,
  height: size.height,
  format: MpImageFormat.srgb,
  data: syntheticSrgbBytes(size),
);

/// Worker that answers each image with its byte length.
///
/// Top-level so it can be sent to the spawned isolate.
NativeTaskWorkerHandler byteLengthWorkerFactory(Object? initialMessage) =>
    (Object? command) => (command! as MpImage).byteLength;

/// Worker that echoes each command back unchanged.
///
/// Top-level so it can be sent to the spawned isolate.
NativeTaskWorkerHandler echoWorkerFactory(Object? initialMessage) =>
    (Object? command) => command;
