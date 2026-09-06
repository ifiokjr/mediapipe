import 'package:mp_audio/mp_audio.dart';

void main() {
  final AudioClassifierResult empty = AudioClassifierResult(const []);
  assert(empty.classifications.isEmpty, 'Expected no classifications.');
}
