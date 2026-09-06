import 'package:test/test.dart';

import '../tool/plan_pub_batch.dart' as planner;

void main() {
  test('keeps package priority while excluding published versions', () async {
    final List<String> result = await planner.pendingPackages(
      version: '0.1.0',
      packageNames: planner.packagePriority,
      versionExists: (String packageName, String version) async =>
          packageName == 'mp_core' || packageName == 'mp_vision',
    );

    expect(result, <String>['mp_camera', 'mp_text', 'mp_audio', 'mp_genai']);
  });

  test('selects dependencies before dependent packages', () {
    expect(planner.packagePriority.first, 'mp_core');
    expect(planner.packagePriority.take(planner.pubDevBatchSize), <String>[
      'mp_core',
      'mp_vision',
      'mp_camera',
      'mp_text',
    ]);
  });
}
