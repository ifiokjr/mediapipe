import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/plan_pub_batch.dart' as planner;

void main() {
  test('plans all six workspace packages in dependency order in a single batch', () async {
    final planner.PubBatchPlan plan = await planner.planPubBatch(
      version: '0.1.6',
      packageNames: planner.packagePriority,
      versionExists: (String packageName, String version) async => false,
    );

    expect(plan.version, '0.1.6');
    expect(plan.packages.first, 'mp_core');
    expect(plan.packages, <String>[
      'mp_core',
      'mp_vision',
      'mp_camera',
      'mp_text',
      'mp_audio',
      'mp_genai',
    ]);
    expect(plan.pendingCount, 6);
    expect(plan.finalBatch, isTrue);
    expect(plan.toJson(), <String, Object>{
      'version': '0.1.6',
      'packages': planner.packagePriority,
      'pendingCount': 6,
      'finalBatch': true,
    });
  });

  test('splits batches when more than the per-run limit is pending', () async {
    final List<String> packages = List<String>.generate(
      planner.pubDevBatchSize + 2,
      (int index) => 'mp_pkg_$index',
      growable: false,
    );

    final planner.PubBatchPlan first = await planner.planPubBatch(
      version: '0.2.0',
      packageNames: packages,
      versionExists: (String packageName, String version) async => false,
    );

    expect(first.packages, packages.take(planner.pubDevBatchSize).toList());
    expect(first.pendingCount, planner.pubDevBatchSize + 2);
    expect(first.finalBatch, isFalse);

    final Set<String> published = first.packages.toSet();
    final planner.PubBatchPlan second = await planner.planPubBatch(
      version: '0.2.0',
      packageNames: packages,
      versionExists: (String packageName, String version) async => published.contains(packageName),
    );

    expect(second.packages, packages.skip(planner.pubDevBatchSize).toList());
    expect(second.pendingCount, 2);
    expect(second.finalBatch, isTrue);
  });

  test('returns an empty final batch when every package is already published', () async {
    final planner.PubBatchPlan plan = await planner.planPubBatch(
      version: '0.1.5',
      packageNames: planner.packagePriority,
      versionExists: (String packageName, String version) async => true,
    );

    expect(plan.packages, isEmpty);
    expect(plan.pendingCount, 0);
    expect(plan.finalBatch, isTrue);
    expect(
      plan.toGithubOutput(),
      'count=0\n'
      'final=true\n'
      'packages=[]\n',
    );
  });

  test('keeps package priority while excluding already published versions', () async {
    final planner.PubBatchPlan plan = await planner.planPubBatch(
      version: '0.1.5',
      packageNames: planner.packagePriority,
      versionExists: (String packageName, String version) async =>
          packageName == 'mp_core' || packageName == 'mp_vision',
    );

    expect(plan.packages, <String>['mp_camera', 'mp_text', 'mp_audio', 'mp_genai']);
    expect(plan.pendingCount, 4);
    expect(plan.finalBatch, isTrue);
  });

  test('rejects non-positive batch sizes', () async {
    await expectLater(
      planner.planPubBatch(
        version: '0.1.5',
        packageNames: planner.packagePriority,
        batchSize: 0,
        versionExists: (String packageName, String version) async => false,
      ),
      throwsArgumentError,
    );
  });

  test('runPlanPubBatch writes JSON output and GITHUB_OUTPUT entries', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp('mp-plan-pub-batch-');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final File outputFile = File.fromUri(tempDir.uri.resolve('github_output.txt'));
    final StringBuffer stdoutBuffer = StringBuffer();

    final planner.PubBatchPlan plan = await planner.runPlanPubBatch(
      const <String>['--version', '0.1.6'],
      versionExists: (String packageName, String version) async => packageName == 'mp_core',
      out: stdoutBuffer,
      githubOutputPath: outputFile.path,
    );

    expect(plan.packages, <String>['mp_vision', 'mp_camera', 'mp_text', 'mp_audio', 'mp_genai']);
    expect(jsonDecode(stdoutBuffer.toString()), <String, Object>{
      'version': '0.1.6',
      'packages': <String>['mp_vision', 'mp_camera', 'mp_text', 'mp_audio', 'mp_genai'],
      'pendingCount': 5,
      'finalBatch': true,
    });
    expect(
      outputFile.readAsStringSync(),
      'count=5\n'
      'final=true\n'
      'packages=["mp_vision","mp_camera","mp_text","mp_audio","mp_genai"]\n',
    );
  });

  test('runPlanPubBatch rejects missing and malformed versions', () async {
    await expectLater(
      planner.runPlanPubBatch(
        const <String>[],
        versionExists: (String packageName, String version) async => false,
      ),
      throwsFormatException,
    );
    await expectLater(
      planner.runPlanPubBatch(const <String>[
        '--version',
        'v0.1.6',
      ], versionExists: (String packageName, String version) async => false),
      throwsFormatException,
    );
  });

  test('main queries pub.dev responses and handles 404, 500, and invalid JSON', () async {
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    String mode = 'normal';
    server.listen((HttpRequest request) async {
      final String packageName = request.uri.pathSegments.last;
      if (mode == 'error') {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
        return;
      }
      if (mode == 'invalid') {
        request.response
          ..statusCode = HttpStatus.ok
          ..write('{"unexpected":true}');
        await request.response.close();
        return;
      }
      if (packageName == 'mp_genai') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final List<Map<String, String>> versions = packageName == 'mp_core'
          ? <Map<String, String>>[
              <String, String>{'version': '0.1.6'},
            ]
          : <Map<String, String>>[
              <String, String>{'version': '0.1.5'},
            ];
      request.response
        ..statusCode = HttpStatus.ok
        ..write(jsonEncode(<String, Object>{'versions': versions}));
      await request.response.close();
    });

    final Uri serverBase = Uri.http('${InternetAddress.loopbackIPv4.address}:${server.port}');
    await HttpOverrides.runWithHttpOverrides(() async {
      await planner.main(const <String>['--version', '0.1.6']);

      mode = 'error';
      await expectLater(
        planner.runPlanPubBatch(const <String>['--version', '0.1.6'], out: StringBuffer()),
        throwsA(isA<HttpException>()),
      );

      mode = 'invalid';
      await expectLater(
        planner.runPlanPubBatch(const <String>['--version', '0.1.6'], out: StringBuffer()),
        throwsFormatException,
      );
    }, _LoopbackHttpOverrides(serverBase));
  });
}

final class _LoopbackHttpOverrides extends HttpOverrides {
  _LoopbackHttpOverrides(this._baseUri);

  final Uri _baseUri;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RedirectHttpClient(_baseUri, super.createHttpClient(context));
}

final class _RedirectHttpClient implements HttpClient {
  _RedirectHttpClient(this._baseUri, this._inner);

  final Uri _baseUri;
  final HttpClient _inner;

  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      _inner.getUrl(_baseUri.replace(path: url.path, query: url.query));

  @override
  void close({bool force = false}) => _inner.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
