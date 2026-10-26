import '../harness.dart';
import '../synthetic.dart';
import 'image_construction.dart';
import 'isolate_transfer.dart';
import 'pixel_conversion.dart';
import 'result_containers.dart';

/// Every suite the regression gate runs, in execution order.
///
/// [size] scales the frame-sized suites; tests pass [tiny] to keep smoke runs
/// fast while the gate uses [hd720].
List<BenchmarkSuite> defaultSuites({FrameSize size = hd720}) => <BenchmarkSuite>[
  pixelConversionSuite(size: size),
  imageConstructionSuite(size: size),
  isolateTransferSuite(size: size),
  resultContainersSuite(),
];
