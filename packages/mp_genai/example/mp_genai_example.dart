import 'package:mp_core/mp_core.dart';
import 'package:mp_genai/mp_genai.dart';

void main() {
  final LlmInferenceOptions options = LlmInferenceOptions(
    baseOptions: BaseOptions(modelAsset: ModelAsset.path('model.task')),
  );
  assert(options.maxTokens == 512, 'Expected the default context size.');
}
