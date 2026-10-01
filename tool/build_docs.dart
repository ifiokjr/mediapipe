import 'dart:io';

const String _siteBase = '/mediapipe/';

Future<void> main() async {
  final String sdkBin = File(Platform.resolvedExecutable).parent.path;
  final String pathSeparator = Platform.isWindows ? ';' : ':';
  final Process process = await Process.start(
    Platform.resolvedExecutable,
    const <String>['run', 'jaspr_cli:jaspr', 'build'],
    workingDirectory: 'docs',
    environment: <String, String>{
      ...Platform.environment,
      'PATH': '$sdkBin$pathSeparator${Platform.environment['PATH'] ?? ''}',
    },
    mode: ProcessStartMode.inheritStdio,
  );
  final int exitCode = await process.exitCode;
  if (exitCode != 0) {
    stderr.writeln('Jaspr exited with status $exitCode.');
    exit(exitCode);
  }

  final Directory output = Directory('docs/build/jaspr');
  if (!output.existsSync()) {
    stderr.writeln('Jaspr did not create ${output.path}.');
    exit(1);
  }

  var htmlFiles = 0;
  for (final FileSystemEntity entity in output.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.html')) continue;
    htmlFiles++;
    final String source = entity.readAsStringSync();
    final String rewritten = source.replaceAll(
      RegExp(r'href="/(?!mediapipe(?:/|"))'),
      'href="$_siteBase',
    );
    if (rewritten != source) entity.writeAsStringSync(rewritten);
  }

  if (htmlFiles == 0) {
    stderr.writeln('Jaspr produced no HTML files in ${output.path}.');
    exit(1);
  }

  final RegExp rootRelativeHref = RegExp(r'href="/(?!mediapipe(?:/|"))');
  for (final FileSystemEntity entity in output.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.html')) {
      final Match? match = rootRelativeHref.firstMatch(entity.readAsStringSync());
      if (match != null) {
        stderr.writeln('Unscoped root link remains in ${entity.path}.');
        exit(1);
      }
    }
  }

  stdout.writeln('Prepared $htmlFiles HTML routes for $_siteBase.');
}
