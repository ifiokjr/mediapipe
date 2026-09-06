import 'package:flutter/material.dart';
import 'package:mp_text/mp_text.dart';

void main() => runApp(const TextTasksExample());

/// Device-test shell for the mobile text task plugin.
final class TextTasksExample extends StatelessWidget {
  /// Creates the example application.
  const TextTasksExample({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      appBar: AppBar(title: const Text('mp_text')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            children: const <Widget>[
              Text('Mobile text task build fixture', style: TextStyle(fontSize: 24)),
              SizedBox(height: 12),
              Text(
                'This application registers the Android and iOS mp_text plugin. '
                'It is used by CI to compile and launch the native plugin. '
                'Model-backed integration tests require a compatible .litertlm '
                'model supplied separately.',
              ),
              SizedBox(height: 24),
              _TaskRow(name: 'TextProofreader', output: TextProofreaderResult),
              _TaskRow(name: 'TextSummarizer', output: TextSummarizerResult),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.name, required this.output});

  final String name;
  final Type output;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: <Widget>[
        const Icon(Icons.memory, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text('$name → $output')),
      ],
    ),
  );
}
