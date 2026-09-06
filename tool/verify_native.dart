import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'native_target.dart';

Future<void> main(List<String> arguments) async {
  if (arguments case ['--target', final String value]) {
    final NativeTarget target = NativeTarget.parse(value);
    final Directory root = _findRepositoryRoot();
    final Directory directory = Directory.fromUri(root.uri.resolve('.mp-sdk/${target.name}/'));
    final File manifestFile = File.fromUri(directory.uri.resolve('manifest.json'));
    final Object? manifest = jsonDecode(await manifestFile.readAsString());
    if (manifest case {
      'mediaPipeVersion': final String mediaPipeVersion,
      'target': final String manifestTarget,
      'libraries': final Map<String, Object?> libraryValues,
    }) {
      if (mediaPipeVersion != 'v1.0.0' || manifestTarget != target.name) {
        throw StateError('Native manifest does not describe ${target.name}.');
      }
      if (!libraryValues.containsKey(target.libraryName)) {
        throw StateError('Native manifest is missing ${target.libraryName}.');
      }
      for (final MapEntry<String, Object?> entry in libraryValues.entries) {
        if (!_isSafeFlatName(entry.key) || entry.value is! String) {
          throw FormatException('Invalid checksum for ${entry.key}.');
        }
        final File library = File.fromUri(directory.uri.resolve(entry.key));
        final Uint8List bytes = await library.readAsBytes();
        final String digest = sha256.convert(bytes).toString();
        if (digest != entry.value) {
          throw StateError('Native library checksum mismatch for ${entry.key}.');
        }
        if (target.isAndroid) {
          verifyAndroidElf(bytes, architecture: target.architecture, name: entry.key);
        }
      }
      stdout.writeln('Verified ${libraryValues.length} libraries for ${target.name}.');
      return;
    }
    throw const FormatException('Invalid native artifact manifest.');
  }
  throw const FormatException('Usage: verify_native.dart --target <os-architecture>');
}

/// Verifies the architecture and 16 KB load-segment alignment of an Android ELF.
void verifyAndroidElf(Uint8List bytes, {required String architecture, required String name}) {
  if (bytes.length < 64 ||
      bytes[0] != 0x7f ||
      bytes[1] != 0x45 ||
      bytes[2] != 0x4c ||
      bytes[3] != 0x46) {
    throw FormatException('$name is not an ELF library.');
  }
  final int elfClass = bytes[4];
  if (bytes[5] != 1 || (elfClass != 1 && elfClass != 2)) {
    throw FormatException('$name uses an unsupported ELF encoding.');
  }
  final ByteData data = ByteData.sublistView(bytes);
  final int expectedClass = architecture == 'arm' ? 1 : 2;
  final int expectedMachine = switch (architecture) {
    'arm' => 40,
    'arm64' => 183,
    'x64' => 62,
    _ => throw FormatException('Unsupported Android architecture: $architecture.'),
  };
  if (elfClass != expectedClass || data.getUint16(18, Endian.little) != expectedMachine) {
    throw FormatException('$name does not match Android $architecture.');
  }

  final int headerOffset = elfClass == 1
      ? data.getUint32(28, Endian.little)
      : data.getUint64(32, Endian.little);
  final int entrySize = data.getUint16(elfClass == 1 ? 42 : 54, Endian.little);
  final int entryCount = data.getUint16(elfClass == 1 ? 44 : 56, Endian.little);
  final int minimumEntrySize = elfClass == 1 ? 32 : 56;
  if (entryCount == 0 || entrySize < minimumEntrySize) {
    throw FormatException('$name has no valid ELF program headers.');
  }

  var loadSegments = 0;
  for (var index = 0; index < entryCount; index += 1) {
    final int offset = headerOffset + (index * entrySize);
    if (offset < 0 || offset + minimumEntrySize > bytes.length) {
      throw FormatException('$name has a truncated ELF program header.');
    }
    if (data.getUint32(offset, Endian.little) != 1) continue;
    loadSegments += 1;
    final int alignment = elfClass == 1
        ? data.getUint32(offset + 28, Endian.little)
        : data.getUint64(offset + 48, Endian.little);
    if (alignment < 16384) {
      throw FormatException('$name has a load segment aligned to $alignment bytes, not 16384.');
    }
  }
  if (loadSegments == 0) {
    throw FormatException('$name has no loadable ELF segments.');
  }
}

bool _isSafeFlatName(String name) =>
    name.isNotEmpty && !name.contains('/') && !name.contains(r'\') && name != '.' && name != '..';

Directory _findRepositoryRoot() {
  Directory current = Directory.current.absolute;
  while (current.parent.path != current.path) {
    if (File.fromUri(current.uri.resolve('pubspec.yaml')).existsSync() &&
        Directory.fromUri(current.uri.resolve('packages/mp_core/')).existsSync()) {
      return current;
    }
    current = current.parent;
  }
  throw StateError('Could not find the MP workspace root.');
}
