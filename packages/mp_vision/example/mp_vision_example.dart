import 'package:mp_core/mp_core.dart';
import 'package:mp_vision/mp_vision.dart';

void main() {
  final FaceDetectorOptions options = FaceDetectorOptions(
    baseOptions: BaseOptions(modelAsset: ModelAsset.path('face_detector.task')),
  );
  assert(options.minDetectionConfidence == 0.5, 'Expected the default confidence.');
}
