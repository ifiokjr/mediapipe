import 'dart:convert';
import 'dart:io';

const List<String> packagePriority = <String>[
  'mp_core',
  'mp_vision',
  'mp_camera',
  'mp_text',
  'mp_audio',
  'mp_genai',
];

// pub.dev's production config (`dart-lang/pub-dev` `app/config/dartlang-pub.yaml`)
// allows 200 `package-published` uploads per 2-minute, 1-hour, and 24-hour window
// per GitHub Actions OIDC repository agent (`scope: user`), and 3/2min, 6/hr,
// 12/24hr per individual package (`scope: package`). Only brand-new packages
// (`package-created`, `scope: user`) are limited to 4 per 2 minutes and 12 per
// 24 hours.
//
// `monochange.toml` enables `publish.rate_limits.enforce = true`, and MonoChange's
// built-in `pub_dev` policy caps a single `publish-packages` invocation at 12
// pending packages. Twelve publishes all six existing packages in one pass while
// staying within MonoChange's enforced ceiling if the workspace grows.
const int pubDevBatchSize = 12;

/// Planned pub.dev publishing batch for a release version.
final class PubBatchPlan {
  /// Creates a publishing batch plan for [version].
  const PubBatchPlan({
    required this.version,
    required this.packages,
    required this.pendingCount,
    required this.finalBatch,
  });

  /// Release version being published.
  final String version;

  /// Packages selected for this run in dependency order.
  final List<String> packages;

  /// Total packages still missing [version] on pub.dev before this run.
  final int pendingCount;

  /// Whether this run publishes the last pending packages for [version].
  final bool finalBatch;

  /// JSON summary written to stdout.
  Map<String, Object> toJson() => <String, Object>{
    'version': version,
    'packages': packages,
    'pendingCount': pendingCount,
    'finalBatch': finalBatch,
  };

  /// Lines appended to `GITHUB_OUTPUT`.
  String toGithubOutput() =>
      'count=${packages.length}\n'
      'final=$finalBatch\n'
      'packages=${jsonEncode(packages)}\n';
}

Future<void> main(List<String> arguments) => runPlanPubBatch(arguments);

/// Parses CLI [arguments], plans the next pub.dev batch, prints the JSON result
/// to [out], and appends step outputs to [githubOutputPath] when provided.
Future<PubBatchPlan> runPlanPubBatch(
  List<String> arguments, {
  Iterable<String> packageNames = packagePriority,
  int batchSize = pubDevBatchSize,
  VersionExists? versionExists,
  StringSink? out,
  String? githubOutputPath,
}) async {
  final String version = _readOption(arguments, '--version');

  if (!RegExp(r'^\d+\.\d+\.\d+([+-][0-9A-Za-z.-]+)?$').hasMatch(version)) {
    throw FormatException('Invalid package version: $version');
  }

  final HttpClient? client = versionExists == null ? HttpClient() : null;
  try {
    final PubBatchPlan plan = await planPubBatch(
      version: version,
      packageNames: packageNames,
      batchSize: batchSize,
      versionExists:
          versionExists ??
          (String packageName, String expectedVersion) =>
              _pubDevVersionExists(client!, packageName, expectedVersion),
    );
    (out ?? stdout).writeln(jsonEncode(plan.toJson()));

    final String? outputPath = githubOutputPath ?? Platform.environment['GITHUB_OUTPUT'];

    if (outputPath != null && outputPath.isNotEmpty) {
      File(outputPath).writeAsStringSync(plan.toGithubOutput(), mode: FileMode.append);
    }

    return plan;
  } finally {
    client?.close(force: true);
  }
}

Future<bool> _pubDevVersionExists(
  HttpClient client,
  String packageName,
  String expectedVersion,
) async {
  final Uri uri = Uri.https('pub.dev', '/api/packages/$packageName');
  final HttpClientRequest request = await client.getUrl(uri);
  request.headers.set(HttpHeaders.userAgentHeader, 'ifiokjr/mediapipe release automation');
  final HttpClientResponse response = await request.close();
  if (response.statusCode == HttpStatus.notFound) return false;
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('pub.dev returned HTTP ${response.statusCode} for $packageName.', uri: uri);
  }

  final Object? decoded = jsonDecode(await utf8.decodeStream(response));
  if (decoded case {'versions': final List<Object?> versions}) {
    return versions.whereType<Map<String, Object?>>().any(
      (Map<String, Object?> release) => release['version'] == expectedVersion,
    );
  }

  throw const FormatException('pub.dev returned an invalid package response.');
}

typedef VersionExists = Future<bool> Function(String packageName, String version);

/// Queries [versionExists] for [packageNames] in dependency order and selects
/// the next batch of at most [batchSize] unpublished packages.
Future<PubBatchPlan> planPubBatch({
  required String version,
  required Iterable<String> packageNames,
  required VersionExists versionExists,
  int batchSize = pubDevBatchSize,
}) async {
  if (batchSize <= 0) {
    throw ArgumentError.value(batchSize, 'batchSize', 'must be positive');
  }

  final List<String> pending = await pendingPackages(
    version: version,
    packageNames: packageNames,
    versionExists: versionExists,
  );
  final List<String> batch = pending.take(batchSize).toList(growable: false);

  return PubBatchPlan(
    version: version,
    packages: batch,
    pendingCount: pending.length,
    finalBatch: pending.length <= batchSize,
  );
}

Future<List<String>> pendingPackages({
  required String version,
  required Iterable<String> packageNames,
  required VersionExists versionExists,
}) async {
  final List<String> pending = <String>[];

  for (final String packageName in packageNames) {
    if (!await versionExists(packageName, version)) pending.add(packageName);
  }

  return pending;
}

String _readOption(List<String> arguments, String name) {
  final int index = arguments.indexOf(name);

  if (index == -1 || index + 1 >= arguments.length) {
    throw FormatException('Missing required option $name.');
  }

  return arguments[index + 1];
}
