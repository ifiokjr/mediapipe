import 'package:flutter_test/flutter_test.dart';
import 'package:mp_text_example/main.dart';

void main() {
  testWidgets('lists the mobile text task types', (WidgetTester tester) async {
    await tester.pumpWidget(const TextTasksExample());

    expect(find.text('TextProofreader → TextProofreaderResult'), findsOneWidget);
    expect(find.text('TextSummarizer → TextSummarizerResult'), findsOneWidget);
  });
}
