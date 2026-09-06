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

const int pubDevBatchSize = 4;

Future<void> main(List<String> arguments) async {
  final String version = _readOption(arguments, '--version');
  if (!RegExp(r'^\d+\.\d+\.\d+([+-][0-9A-Za-z.-]+)?$').hasMatch(version)) {
    throw FormatException('Invalid package version: $version');
  }

  final HttpClient client = HttpClient();
  try {
    final List<String> pending = await pendingPackages(
      version: version,
      packageNames: packagePriority,
      versionExists: (String packageName, String expectedVersion) async {
        final Uri uri = Uri.https('pub.dev', '/api/packages/$packageName');
        final HttpClientRequest request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.userAgentHeader, 'ifiokjr/mediapipe release automation');
        final HttpClientResponse response = await request.close();
        if (response.statusCode == HttpStatus.notFound) return false;
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(
            'pub.dev returned HTTP ${response.statusCode} for $packageName.',
            uri: uri,
          );
        }
        final Object? decoded = jsonDecode(await utf8.decodeStream(response));
        if (decoded case {'versions': final List<Object?> versions}) {
          return versions.whereType<Map<String, Object?>>().any(
            (Map<String, Object?> release) => release['version'] == expectedVersion,
          );
        }
        throw const FormatException('pub.dev returned an invalid package response.');
      },
    );
    final List<String> batch = pending.take(pubDevBatchSize).toList(growable: false);
    final Map<String, Object> result = <String, Object>{
      'version': version,
      'packages': batch,
      'pendingCount': pending.length,
      'finalBatch': pending.length <= pubDevBatchSize,
    };
    stdout.writeln(jsonEncode(result));

    final String? githubOutput = Platform.environment['GITHUB_OUTPUT'];
    if (githubOutput != null && githubOutput.isNotEmpty) {
      File(githubOutput).writeAsStringSync(
        'count=${batch.length}\n'
        'final=${pending.length <= pubDevBatchSize}\n'
        'packages=${jsonEncode(batch)}\n',
        mode: FileMode.append,
      );
    }
  } finally {
    client.close(force: true);
  }
}

typedef VersionExists = Future<bool> Function(String packageName, String version);

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
