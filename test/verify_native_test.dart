import 'dart:typed_data';

import 'package:test/test.dart';

import '../tool/verify_native.dart';

void main() {
  test('accepts a 16 KB aligned Android arm64 ELF', () {
    expect(
      () => verifyAndroidElf(
        _elf(elfClass: 2, machine: 183, alignment: 16384),
        architecture: 'arm64',
        name: 'libmediapipe.so',
      ),
      returnsNormally,
    );
  });

  test('accepts a 16 KB aligned Android arm ELF', () {
    expect(
      () => verifyAndroidElf(
        _elf(elfClass: 1, machine: 40, alignment: 16384),
        architecture: 'arm',
        name: 'libmediapipe.so',
      ),
      returnsNormally,
    );
  });

  test('accepts a 16 KB aligned Android x64 ELF', () {
    expect(
      () => verifyAndroidElf(
        _elf(elfClass: 2, machine: 62, alignment: 16384),
        architecture: 'x64',
        name: 'libmediapipe.so',
      ),
      returnsNormally,
    );
  });

  test('rejects a 4 KB aligned Android ELF', () {
    expect(
      () => verifyAndroidElf(
        _elf(elfClass: 2, machine: 183, alignment: 4096),
        architecture: 'arm64',
        name: 'libmediapipe.so',
      ),
      throwsFormatException,
    );
  });

  test('rejects an ELF built for another architecture', () {
    expect(
      () => verifyAndroidElf(
        _elf(elfClass: 2, machine: 62, alignment: 16384),
        architecture: 'arm64',
        name: 'libmediapipe.so',
      ),
      throwsFormatException,
    );
  });
}

Uint8List _elf({required int elfClass, required int machine, required int alignment}) {
  final Uint8List bytes = Uint8List(128);
  bytes.setAll(0, const <int>[0x7f, 0x45, 0x4c, 0x46]);
  bytes[4] = elfClass;
  bytes[5] = 1;
  final ByteData data = ByteData.sublistView(bytes);
  data.setUint16(18, machine, Endian.little);
  if (elfClass == 1) {
    data
      ..setUint32(28, 64, Endian.little)
      ..setUint16(42, 32, Endian.little)
      ..setUint16(44, 1, Endian.little)
      ..setUint32(64, 1, Endian.little)
      ..setUint32(92, alignment, Endian.little);
  } else {
    data
      ..setUint64(32, 64, Endian.little)
      ..setUint16(54, 56, Endian.little)
      ..setUint16(56, 1, Endian.little)
      ..setUint32(64, 1, Endian.little)
      ..setUint64(112, alignment, Endian.little);
  }
  return bytes;
}
