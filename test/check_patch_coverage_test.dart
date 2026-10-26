import 'dart:io';

import 'package:test/test.dart';

import '../tool/check_patch_coverage.dart' as coverage;

const String sampleDiff = '''
diff --git a/packages/mp_core/lib/src/image.dart b/packages/mp_core/lib/src/image.dart
index 1111111..2222222 100644
--- a/packages/mp_core/lib/src/image.dart
+++ b/packages/mp_core/lib/src/image.dart
@@ -10,2 +10,3 @@
 context
-removed
+added one
+added two
 context
@@ -40 +41 @@
-old single
+new single
diff --git a/gone.dart b/gone.dart
deleted file mode 100644
--- a/gone.dart
+++ /dev/null
@@ -1 +0 @@
-deleted
diff --git a/benchmarks/lib/src/new.dart b/benchmarks/lib/src/new.dart
new file mode 100644
--- /dev/null
+++ b/benchmarks/lib/src/new.dart
@@ -0,0 +1,2 @@
+first
+second
''';

void main() {
  group('parseAddedLines', () {
    test('collects new-side line numbers and skips deletions', () {
      final Map<String, Set<int>> added = coverage.parseAddedLines(sampleDiff);

      expect(added['packages/mp_core/lib/src/image.dart'], <int>{10, 11, 12, 41});
      expect(added['benchmarks/lib/src/new.dart'], <int>{1, 2});
      expect(added.containsKey('gone.dart'), isFalse);
    });
  });

  group('parseLcov', () {
    test('collects and merges line hits per file', () {
      const String lcov = '''
SF:packages/mp_core/lib/src/image.dart
DA:11,3
DA:12,0
DA:99,7
end_of_record
SF:packages/mp_core/lib/src/image.dart
DA:12,1
end_of_record
SF:packages/other/lib/x.dart
DA:1,2
end_of_record
''';

      expect(coverage.parseLcov(lcov), <String, Map<int, int>>{
        'packages/mp_core/lib/src/image.dart': <int, int>{11: 3, 12: 1, 99: 7},
        'packages/other/lib/x.dart': <int, int>{1: 2},
      });
    });
  });

  group('globMatch', () {
    test('supports ** across separators and * within one', () {
      expect(coverage.globMatch('**/*.g.dart', 'a/b/c.g.dart'), isTrue);
      // `**` also matches zero segments.
      expect(coverage.globMatch('**/*.g.dart', 'c.g.dart'), isTrue);
      expect(coverage.globMatch('a/**/b.dart', 'a/b.dart'), isTrue);
      expect(coverage.globMatch('a/**/b.dart', 'a/x/b.dart'), isTrue);
      expect(coverage.globMatch('a/**/b.dart', 'x/a/b.dart'), isFalse);
      expect(
        coverage.globMatch('packages/*/lib/**/*.dart', 'packages/mp_core/lib/src/a.dart'),
        isTrue,
      );
      expect(coverage.globMatch('packages/*/lib/**/*.dart', 'packages/a/b/lib/x.dart'), isFalse);
      expect(coverage.globMatch('packages/*/lib/**/*.dart', 'packages/mp_core/lib/a.dart'), isTrue);
      expect(coverage.globMatch('**/web/**', 'packages/mp_core/lib/src/web/support.dart'), isTrue);
      expect(coverage.globMatch('**/web.dart', 'packages/mp_core/lib/web.dart'), isTrue);
      expect(coverage.globMatch('**/web.dart', 'packages/mp_core/lib/webby.dart'), isFalse);
      expect(coverage.globMatch('tool/**/*.dart', 'tool/a/b.dart'), isTrue);
      expect(coverage.globMatch('a?c.dart', 'abc.dart'), isTrue);
      expect(coverage.globMatch('a?c.dart', 'abbc.dart'), isFalse);
    });
  });

  group('resolveLcovPath', () {
    late Directory temporary;

    setUp(() {
      temporary = Directory.systemTemp.createTempSync('patch_coverage_');
      Directory('${temporary.path}/pkg/lib').createSync(recursive: true);
      File('${temporary.path}/pkg/lib/a.dart').writeAsStringSync('');
    });

    tearDown(() {
      temporary.deleteSync(recursive: true);
    });

    test('resolves absolute, root-relative, and prefixed paths', () {
      final String root = temporary.path;

      expect(coverage.resolveLcovPath(root, '', '$root/pkg/lib/a.dart'), 'pkg/lib/a.dart');
      expect(coverage.resolveLcovPath(root, '', 'pkg/lib/a.dart'), 'pkg/lib/a.dart');
      expect(coverage.resolveLcovPath(root, 'pkg', 'lib/a.dart'), 'pkg/lib/a.dart');
      expect(coverage.resolveLcovPath(root, '', '/elsewhere/a.dart'), isNull);
      expect(coverage.resolveLcovPath(root, 'pkg', 'lib/missing.dart'), isNull);
    });
  });

  group('computePatchCoverage', () {
    test('classifies changed lines as covered, uncovered, or ignored', () {
      final coverage.PatchCoverageResult result = coverage.computePatchCoverage(
        changed: <String, Set<int>>{
          'packages/mp_core/lib/src/image.dart': <int>{11, 12, 13},
          'packages/mp_core/lib/src/untested.dart': <int>{5},
          'packages/mp_core/lib/src/runtime_native.dart': <int>{7},
          'packages/mp_core/lib/src/generated.g.dart': <int>{7},
          'packages/mp_core/lib/src/web/support.dart': <int>{9},
          'docs/content/x.md': <int>{1},
          'packages/mp_core/lib/src/barrel.dart': <int>{1},
        },
        hits: <String, Map<int, int>>{
          // Line 12 is instrumented but never ran; line 13 has no record and
          // is treated as non-executable.
          'packages/mp_core/lib/src/image.dart': <int, int>{11: 2, 12: 0},
          'packages/mp_core/lib/src/barrel.dart': <int, int>{},
        },
        includes: coverage.defaultIncludes,
        excludes: coverage.defaultExcludes,
      );

      expect(result.files, hasLength(3));

      // A loaded file with no executable lines at all is fully covered.
      final coverage.FileCoverage barrel = result.files[0];

      expect(barrel.path, 'packages/mp_core/lib/src/barrel.dart');
      expect(barrel.hasCoverageData, isTrue);
      expect(barrel.uncoveredLines, isEmpty);
      expect(barrel.isCovered, isTrue);

      final coverage.FileCoverage image = result.files[1];

      expect(image.path, 'packages/mp_core/lib/src/image.dart');
      expect(image.uncoveredLines, <int>{12});
      expect(image.isCovered, isFalse);

      final coverage.FileCoverage untested = result.files[2];

      expect(untested.hasCoverageData, isFalse);
      expect(untested.uncoveredLines, <int>{5});
      expect(untested.isCovered, isFalse);

      expect(result.percent, closeTo(60, 0.1));
      expect(result.isComplete, isFalse);
    });

    test('is complete when everything changed is covered', () {
      final coverage.PatchCoverageResult result = coverage.computePatchCoverage(
        changed: <String, Set<int>>{
          'benchmarks/lib/src/harness.dart': <int>{3, 4},
        },
        hits: <String, Map<int, int>>{
          'benchmarks/lib/src/harness.dart': <int, int>{3: 1, 4: 2},
        },
        includes: coverage.defaultIncludes,
        excludes: coverage.defaultExcludes,
      );

      expect(result.percent, 100);
      expect(result.isComplete, isTrue);
    });

    test('with no changed production files the result is trivially complete', () {
      final coverage.PatchCoverageResult result = coverage.computePatchCoverage(
        changed: <String, Set<int>>{
          'README.md': <int>{2},
        },
        hits: const <String, Map<int, int>>{},
        includes: coverage.defaultIncludes,
        excludes: coverage.defaultExcludes,
      );

      expect(result.files, isEmpty);
      expect(result.percent, 100);
      expect(result.isComplete, isTrue);
    });
  });

  group('renderReport', () {
    test('lists uncovered lines and files without data', () {
      final String report = coverage.renderReport(
        const coverage.PatchCoverageResult(
          files: <coverage.FileCoverage>[
            coverage.FileCoverage(
              path: 'packages/mp_core/lib/src/a.dart',
              changedLines: <int>{4},
              uncoveredLines: <int>{},
              hasCoverageData: true,
            ),
            coverage.FileCoverage(
              path: 'packages/mp_core/lib/src/b.dart',
              changedLines: <int>{7, 8},
              uncoveredLines: <int>{8},
              hasCoverageData: true,
            ),
            coverage.FileCoverage(
              path: 'packages/mp_core/lib/src/c.dart',
              changedLines: <int>{1},
              uncoveredLines: <int>{1},
              hasCoverageData: false,
            ),
          ],
        ),
        100,
      );

      expect(report, contains('### Patch coverage: 50.0%'));
      expect(report, contains('| packages/mp_core/lib/src/a.dart | 1 | — |'));
      expect(report, contains('| packages/mp_core/lib/src/b.dart | 2 | 8 |'));
      expect(report, contains('| packages/mp_core/lib/src/c.dart | 1 | no coverage data |'));
      expect(report, contains('Required minimum is 100.0%.'));
    });

    test('short-circuits when nothing changed', () {
      expect(
        coverage.renderReport(
          const coverage.PatchCoverageResult(files: <coverage.FileCoverage>[]),
          100,
        ),
        contains('No changed production lines to verify.'),
      );
    });
  });

  group('expandLcovPattern', () {
    late Directory temporary;

    setUp(() {
      temporary = Directory.systemTemp.createTempSync('patch_coverage_glob_');
      for (final String path in <String>[
        'coverage/lcov.info',
        'packages/mp_core/coverage/lcov.info',
        'packages/mp_vision/coverage/lcov.info',
        'packages/mp_core/coverage/ignored.txt',
      ]) {
        final File file = File('${temporary.path}/$path');

        file.parent.createSync(recursive: true);
        file.writeAsStringSync('');
      }
    });

    tearDown(() {
      temporary.deleteSync(recursive: true);
    });

    test('expands single-star patterns without descending into trees', () {
      expect(
        coverage.expandLcovPattern(temporary.path, 'packages/*/coverage/lcov.info'),
        unorderedMatches(<String>[
          'packages/mp_core/coverage/lcov.info',
          'packages/mp_vision/coverage/lcov.info',
        ]),
      );
      expect(coverage.expandLcovPattern(temporary.path, 'coverage/lcov.info'), <String>[
        'coverage/lcov.info',
      ]);
      expect(coverage.expandLcovPattern(temporary.path, 'missing/*/lcov.info'), isEmpty);
    });
  });

  group('isDirectiveOnly', () {
    test('accepts barrel files and rejects executable code', () {
      expect(
        coverage.isDirectiveOnly('''
/// Shared primitives.
library;

// A comment.
export 'src/a.dart';
export 'src/b.dart' show B;
import 'dart:async';
part 'c.dart';
@Deprecated('x')
/* block
   comment */ export 'src/d.dart';
'''),
        isTrue,
      );
      expect(coverage.isDirectiveOnly("export 'a.dart';\nint x = 1;\n"), isFalse);
      expect(coverage.isDirectiveOnly('/* open */ void f() {}'), isFalse);
      expect(coverage.isDirectiveOnly(''), isTrue);
    });
  });

  group('runPatchCoverageCheck', () {
    late Directory repository;
    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      repository = Directory.systemTemp.createTempSync('patch_coverage_repo_');
      out = StringBuffer();
      err = StringBuffer();
    });

    tearDown(() {
      repository.deleteSync(recursive: true);
    });

    Future<int> run(List<String> arguments) =>
        coverage.runPatchCoverageCheck(arguments, root: repository.path, out: out, err: err);

    Future<void> git(List<String> arguments) async {
      final ProcessResult result = await Process.run(
        'git',
        arguments,
        workingDirectory: repository.path,
      );

      expect(result.exitCode, 0, reason: 'git ${arguments.join(' ')} failed: ${result.stderr}');
    }

    void writeLcov(String relativePath, String contents) {
      File('${repository.path}/$relativePath')
        ..createSync(recursive: true)
        ..writeAsStringSync(contents);
    }

    /// Builds a two-commit fixture: the second commit adds a covered line, an
    /// uncovered line, and padding to `a.dart` (six changed lines) plus one
    /// export line to the `demo.dart` barrel.
    Future<void> buildFixture() async {
      await git(<String>['init', '--initial-branch=main']);
      await git(<String>['config', 'user.email', 'test@example.com']);
      await git(<String>['config', 'user.name', 'Test']);

      final File source = File('${repository.path}/packages/demo/lib/a.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('int base() => 1;\n');
      final File barrel = File('${repository.path}/packages/demo/lib/demo.dart')
        ..writeAsStringSync("export 'a.dart';\n");
      await git(<String>['add', '.']);
      await git(<String>['commit', '-m', 'base']);

      source.writeAsStringSync(
        'int base() => 1;\n\nint covered() => 2;\n\nint missed() => 3;\n\n// comment\n',
      );
      barrel.writeAsStringSync("export 'a.dart';\nexport 'b.dart';\n");
      await git(<String>['add', '.']);
      await git(<String>['commit', '-m', 'head']);
    }

    test('passes when every executable changed line ran', () async {
      await buildFixture();
      writeLcov('coverage/lcov.info', '''
SF:packages/demo/lib/a.dart
DA:3,1
DA:5,1
end_of_record
SF:elsewhere/unknown.dart
DA:1,1
end_of_record
''');

      final int exitCode = await run(<String>['--base', 'HEAD~1', '--summary', 'summary.md']);

      expect(exitCode, 0, reason: '$out$err');
      expect(out.toString(), contains('Patch coverage: 100.0%'));
      expect(out.toString(), contains('| packages/demo/lib/demo.dart | 1 | — |'));
      expect(err.toString(), contains('Skipping unresolvable lcov path "elsewhere/unknown.dart"'));
      expect(File('${repository.path}/summary.md').readAsStringSync(), contains('100.0%'));
    });

    test('fails on uncovered and unmeasured changed lines', () async {
      await buildFixture();
      writeLcov('coverage/lcov.info', '''
SF:packages/demo/lib/a.dart
DA:3,1
DA:5,0
end_of_record
''');

      expect(await run(<String>['--base', 'HEAD~1']), coverage.coverageFailureExitCode);
      // Seven changed lines across both files, one uncovered executable line.
      expect(out.toString(), contains('Patch coverage: 85.7%'));
      expect(out.toString(), contains('| packages/demo/lib/a.dart | 6 | 5 |'));

      // A lower minimum still fails while an executable line is uncovered.
      out.clear();
      expect(
        await run(<String>['--base', 'HEAD~1', '--min', '50']),
        coverage.coverageFailureExitCode,
      );

      // A changed production file with no lcov record at all also fails.
      File('${repository.path}/packages/demo/lib/b.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('int added() => 4;\n');
      await git(<String>['add', '.']);
      await git(<String>['commit', '-m', 'unmeasured file']);
      out.clear();

      expect(await run(<String>['--base', 'HEAD~1']), coverage.coverageFailureExitCode);
      expect(out.toString(), contains('| packages/demo/lib/b.dart | 1 | no coverage data |'));
    });

    test('reads explicit lcov files with package prefixes and skips missing ones', () async {
      await buildFixture();
      writeLcov('packages/demo/coverage/lcov.info', '''
SF:lib/a.dart
DA:3,1
DA:5,1
end_of_record
''');

      final int exitCode = await run(<String>[
        '--base',
        'HEAD~1',
        '--lcov',
        'packages/demo/coverage/lcov.info@packages/demo',
        '--lcov',
        '${repository.path}/missing.info',
      ]);

      expect(exitCode, 0, reason: '$out$err');
      expect(out.toString(), contains('Reading 2 lcov file(s).'));
    });

    test('fails when no lcov files exist', () async {
      await buildFixture();

      expect(await run(<String>['--base', 'HEAD~1']), coverage.coverageFailureExitCode);
      expect(err.toString(), contains('No lcov files found'));
    });

    test('reports git failures', () async {
      await buildFixture();
      writeLcov('coverage/lcov.info', 'SF:x\nend_of_record\n');

      expect(await run(<String>['--base', 'no-such-ref']), coverage.coverageFailureExitCode);
      expect(err.toString(), contains('git merge-base no-such-ref HEAD failed'));
    });

    test('rejects invalid usage', () async {
      expect(await run(<String>[]), coverage.usageExitCode);
      expect(err.toString(), contains('--base is required'));

      err.clear();
      expect(await run(<String>['--base']), coverage.usageExitCode);
      expect(err.toString(), contains('requires a value'));

      err.clear();
      expect(await run(<String>['--base', 'x', '--min', '200']), coverage.usageExitCode);
      expect(err.toString(), contains('between 0 and 100'));

      err.clear();
      expect(await run(<String>['--bogus']), coverage.usageExitCode);
      expect(err.toString(), contains('Unknown option "--bogus"'));
    });

    test('main forwards the exit code for the working directory', () async {
      await buildFixture();
      writeLcov('coverage/lcov.info', '''
SF:packages/demo/lib/a.dart
DA:3,1
DA:5,1
end_of_record
''');
      final Directory previous = Directory.current;
      final int previousExitCode = exitCode;

      try {
        Directory.current = repository.path;
        await coverage.main(<String>['--base', 'HEAD~1']);

        expect(exitCode, 0);
      } finally {
        Directory.current = previous;
        exitCode = previousExitCode;
      }
    });
  });
}
