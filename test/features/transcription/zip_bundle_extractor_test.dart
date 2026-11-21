import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/zip_bundle_extractor.dart';

/// The runtime bundle's layout, with the manifest last as in the release.
final Map<String, List<int>> _bundle = {
  'bin/qwen3-asr.exe': utf8.encode('qwen runtime binary'),
  'bin/whisper-cli.exe': utf8.encode('whisper runtime binary'),
  'licenses/whisper.cpp-LICENSE': utf8.encode('MIT'),
  'runtime-manifest.json': utf8.encode('{"runtimePatchRevision":"r1"}'),
};

void main() {
  late Directory temp;
  late File archive;
  late Directory staging;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('zip_bundle_extractor_test');
    archive = File('${temp.path}${Platform.pathSeparator}bundle.zip');
    staging = Directory('${temp.path}${Platform.pathSeparator}staging');
    await staging.create();
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  /// Writes [files] the way a fake tool would have extracted them.
  Future<void> writeTree(
    Directory root,
    Map<String, List<int>> files, {
    Set<String> skip = const {},
  }) async {
    for (final entry in files.entries) {
      if (skip.contains(entry.key)) continue;
      final file = File(
        [root.path, ...entry.key.split('/')].join(Platform.pathSeparator),
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.value);
    }
  }

  group('ZipCentralDirectory', () {
    test('lists files, directories and sizes without extracting', () async {
      await archive.writeAsBytes(
        _zip({
          'bin/': const <int>[],
          ..._bundle,
        }),
      );

      final entries = await ZipCentralDirectory.read(archive);

      expect(entries.map((entry) => entry.path), [
        'bin/',
        'bin/qwen3-asr.exe',
        'bin/whisper-cli.exe',
        'licenses/whisper.cpp-LICENSE',
        'runtime-manifest.json',
      ]);
      expect(entries.first.isDirectory, isTrue);
      expect(entries.last.name, 'runtime-manifest.json');
      expect(
        entries.last.uncompressedSize,
        _bundle['runtime-manifest.json']!.length,
      );
    });

    test('normalises Windows separators written by old archivers', () async {
      await archive.writeAsBytes(
        _zip({r'bin\qwen3-asr.exe': utf8.encode('x')}),
      );

      final entries = await ZipCentralDirectory.read(archive);

      expect(entries.single.path, 'bin/qwen3-asr.exe');
      expect(entries.single.name, 'qwen3-asr.exe');
    });

    test('reads ZIP64 end records and size fields', () async {
      await archive.writeAsBytes(_zip(_bundle, zip64: true));

      final entries = await ZipCentralDirectory.read(archive);

      expect(entries.map((entry) => entry.path), _bundle.keys);
      expect(
        entries.map((entry) => entry.uncompressedSize),
        _bundle.values.map((bytes) => bytes.length),
      );
    });

    test('rejects files that are not zip archives', () async {
      await archive.writeAsString('<html>rate limited</html>');

      await expectLater(
        ZipCentralDirectory.read(archive),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects entries that escape the extraction directory', () {
      expect(
        () => ZipCentralDirectory.normalisePath('../evil.dll'),
        throwsFormatException,
      );
      expect(
        () => ZipCentralDirectory.normalisePath(r'C:\Windows\evil.dll'),
        throwsFormatException,
      );
      expect(
        () => ZipCentralDirectory.normalisePath('/etc/passwd'),
        throwsFormatException,
      );
      expect(ZipCentralDirectory.normalisePath('./bin/a.exe'), 'bin/a.exe');
    });
  });

  group('ZipBundleExtractor on Windows', () {
    late List<String> executables;
    late List<Map<String, String>?> environments;

    setUp(() {
      executables = [];
      environments = [];
    });

    ZipBundleExtractor extractor(
      Future<ProcessResult> Function(int call) behaviour, {
      Future<int?> Function(String path)? freeSpaceReader,
    }) {
      return ZipBundleExtractor(
        isWindows: true,
        environment: const {'SystemRoot': r'C:\Windows'},
        executableExists: (_) => true,
        freeSpaceReader: freeSpaceReader,
        runProcess: (executable, arguments, {environment}) {
          executables.add(executable);
          environments.add(environment);
          return behaviour(executables.length);
        },
      );
    }

    test(
      'falls back when a tool exits 0 but leaves the manifest out',
      () async {
        await archive.writeAsBytes(_zip(_bundle));

        final report = await extractor((call) async {
          // tar stops before the last entry; .NET extracts everything.
          await writeTree(
            staging,
            _bundle,
            skip: call == 1 ? {'runtime-manifest.json'} : const {},
          );
          return ProcessResult(call, 0, '', '');
        }).extract(archive, staging);

        expect(executables, [
          r'C:\Windows\System32\tar.exe',
          r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
        ]);
        expect(report.method, '.NET ZipFile');
        expect(report.attempts.first.method, 'tar');
        expect(report.attempts.first.missing, ['runtime-manifest.json']);
        expect(report.archiveContains('runtime-manifest.json'), isTrue);
        expect(
          await File(
            '${staging.path}${Platform.pathSeparator}runtime-manifest.json',
          ).exists(),
          isTrue,
        );
        // Windows PowerShell must not inherit a PowerShell 7 module path.
        expect(
          environments[1]?['PSModulePath'],
          r'C:\Windows\System32\WindowsPowerShell\v1.0\Modules',
        );
      },
    );

    test('treats a truncated file as missing', () async {
      await archive.writeAsBytes(_zip(_bundle));

      final report = await extractor((call) async {
        await writeTree(staging, {
          ..._bundle,
          if (call == 1) 'bin/qwen3-asr.exe': utf8.encode('qwen'),
        });
        return ProcessResult(call, 0, '', '');
      }).extract(archive, staging);

      expect(report.attempts.first.missing, ['bin/qwen3-asr.exe']);
      expect(report.method, '.NET ZipFile');
    });

    test('reports every attempt when no tool succeeds', () async {
      await archive.writeAsBytes(_zip(_bundle));

      final error = await _extractionFailure(
        extractor((call) async {
          if (call == 1) {
            await writeTree(staging, {'bin/qwen3-asr.exe': _bundle.values.first});
            return ProcessResult(call, 0, '', '');
          }
          return ProcessResult(call, 1, '', 'Access to the path is denied.');
        }).extract(archive, staging),
      );

      expect(error.attempts.map((attempt) => attempt.method), [
        'tar',
        '.NET ZipFile',
        'Expand-Archive',
      ]);
      expect(error.message, contains('tar、.NET ZipFile、Expand-Archive'));
      expect(error.details, contains('runtime-manifest.json'));
      expect(error.details, contains('Access to the path is denied.'));
      // Nothing half-extracted is left behind for the installer to pick up.
      expect(await staging.list().isEmpty, isTrue);
    });

    test('skips tar.exe on Windows versions without it', () async {
      await archive.writeAsBytes(_zip(_bundle));
      final noTar = ZipBundleExtractor(
        isWindows: true,
        environment: const {'SystemRoot': r'C:\Windows'},
        executableExists: (path) => !path.endsWith('tar.exe'),
        runProcess: (executable, arguments, {environment}) async {
          executables.add(executable);
          await writeTree(staging, _bundle);
          return ProcessResult(0, 0, '', '');
        },
      );

      final report = await noTar.extract(archive, staging);

      expect(report.method, '.NET ZipFile');
      expect(executables, hasLength(1));
    });

    test('stops before extracting when the disk is too full', () async {
      await archive.writeAsBytes(_zip(_bundle));

      final error = await _extractionFailure(
        extractor(
          (call) async => ProcessResult(call, 0, '', ''),
          freeSpaceReader: (_) async => 1024,
        ).extract(archive, staging),
      );

      expect(executables, isEmpty);
      expect(error.message, contains('磁盘剩余空间不足'));
      expect(error.attempts.single.method, 'free-space');
    });

    test('accepts any non-empty output when the archive is unreadable', () async {
      await archive.writeAsString('not a zip, but the tools may know better');

      final report = await extractor((call) async {
        await writeTree(staging, {'runtime-manifest.json': utf8.encode('{}')});
        return ProcessResult(call, 0, '', '');
      }).extract(archive, staging);

      expect(report.method, 'tar');
      expect(report.archiveEntries, isNull);
      expect(report.archiveContains('runtime-manifest.json'), isNull);
    });

    test('refuses archives with unsafe paths before running a tool', () async {
      await archive.writeAsBytes(_zip({'../outside.dll': utf8.encode('x')}));

      final error = await _extractionFailure(
        extractor(
          (call) async => ProcessResult(call, 0, '', ''),
        ).extract(archive, staging),
      );

      expect(executables, isEmpty);
      expect(error.message, contains('不安全'));
    });

    test('reports a missing manifest in the archive itself', () async {
      final withoutManifest = Map.of(_bundle)..remove('runtime-manifest.json');
      await archive.writeAsBytes(_zip(withoutManifest));

      final report = await extractor((call) async {
        await writeTree(staging, withoutManifest);
        return ProcessResult(call, 0, '', '');
      }).extract(archive, staging);

      expect(report.archiveContains('runtime-manifest.json'), isFalse);
    });
  });

  test(
    'extracts a real archive with the platform tools',
    () async {
      await archive.writeAsBytes(_zip(_bundle));

      final report = await ZipBundleExtractor().extract(archive, staging);

      expect(report.archiveContains('runtime-manifest.json'), isTrue);
      for (final entry in _bundle.entries) {
        final file = File(
          [staging.path, ...entry.key.split('/')].join(Platform.pathSeparator),
        );
        expect(await file.readAsBytes(), entry.value, reason: entry.key);
      }
      expect(
        await ZipBundleExtractor.describeTree(staging),
        containsAll(_bundle.keys),
      );
    },
    skip: Platform.isWindows || File('/usr/bin/unzip').existsSync()
        ? false
        : 'unzip is not installed',
  );
}

Future<ZipExtractionException> _extractionFailure(
  Future<ZipExtractionReport> future,
) async {
  try {
    await future;
  } on ZipExtractionException catch (error) {
    return error;
  }
  fail('expected a ZipExtractionException');
}

/// Builds a stored (uncompressed) zip archive.
Uint8List _zip(Map<String, List<int>> files, {bool zip64 = false}) {
  final out = BytesBuilder();
  final directory = BytesBuilder();
  var count = 0;

  void u16(BytesBuilder b, int value) =>
      b.add((ByteData(2)..setUint16(0, value, Endian.little)).buffer.asUint8List());
  void u32(BytesBuilder b, int value) =>
      b.add((ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List());
  void u64(BytesBuilder b, int value) =>
      b.add((ByteData(8)..setUint64(0, value, Endian.little)).buffer.asUint8List());

  for (final entry in files.entries) {
    final name = utf8.encode(entry.key);
    final data = entry.value;
    final crc = _crc32(data);
    final offset = out.length;
    final extra = BytesBuilder();
    if (zip64) {
      u16(extra, 0x0001);
      u16(extra, 24);
      u64(extra, data.length);
      u64(extra, data.length);
      u64(extra, offset);
    }
    final extraBytes = extra.takeBytes();

    u32(out, 0x04034b50);
    u16(out, zip64 ? 45 : 20);
    u16(out, 0x800);
    u16(out, 0);
    u16(out, 0);
    u16(out, 0x21);
    u32(out, crc);
    u32(out, data.length);
    u32(out, data.length);
    u16(out, name.length);
    u16(out, 0);
    out.add(name);
    out.add(data);

    u32(directory, 0x02014b50);
    u16(directory, zip64 ? 45 : 20);
    u16(directory, zip64 ? 45 : 20);
    u16(directory, 0x800);
    u16(directory, 0);
    u16(directory, 0);
    u16(directory, 0x21);
    u32(directory, crc);
    u32(directory, zip64 ? 0xffffffff : data.length);
    u32(directory, zip64 ? 0xffffffff : data.length);
    u16(directory, name.length);
    u16(directory, extraBytes.length);
    u16(directory, 0);
    u16(directory, 0);
    u16(directory, 0);
    u32(directory, 0);
    u32(directory, zip64 ? 0xffffffff : offset);
    directory.add(name);
    directory.add(extraBytes);
    count++;
  }

  final directoryOffset = out.length;
  final directoryBytes = directory.takeBytes();
  out.add(directoryBytes);

  if (zip64) {
    final recordOffset = out.length;
    u32(out, 0x06064b50);
    u64(out, 44);
    u16(out, 45);
    u16(out, 45);
    u32(out, 0);
    u32(out, 0);
    u64(out, count);
    u64(out, count);
    u64(out, directoryBytes.length);
    u64(out, directoryOffset);

    u32(out, 0x07064b50);
    u32(out, 0);
    u64(out, recordOffset);
    u32(out, 1);
  }

  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, zip64 ? 0xffff : count);
  u16(out, zip64 ? 0xffff : count);
  u32(out, zip64 ? 0xffffffff : directoryBytes.length);
  u32(out, zip64 ? 0xffffffff : directoryOffset);
  u16(out, 0);
  return out.takeBytes();
}

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}
