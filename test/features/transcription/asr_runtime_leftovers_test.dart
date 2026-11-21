import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_asr_managed_storage_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_managed_storage_service.dart';

final _sep = Platform.pathSeparator;

String _p(String root, List<String> parts) => [root, ...parts].join(_sep);

Future<File> _write(String root, List<String> parts, String content) async {
  final file = File(_p(root, parts));
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
  return file;
}

Future<String?> _read(String root, List<String> parts) async {
  final file = File(_p(root, parts));
  return await file.exists() ? file.readAsString() : null;
}

const _bundleBin = ['bundle', 'bin', 'qwen3-asr.exe'];
const _whisper = ['models', 'whisper', 'ggml-large-v3.bin'];
const _health = ['.runtime-health-v1.json'];
const _qwenMarker = [
  'models',
  'qwen',
  'Qwen--Qwen3-ASR-1.7B',
  '.lyricforge-model.json',
];

/// A sandbox with a support folder, the user's `Models/LyricForge/ASRRuntime`
/// and the nested copy an older build created inside it.
class _Disk {
  _Disk(this.sandbox)
    : support = _p(sandbox.path, ['support']),
      outer = _p(sandbox.path, ['Models', 'LyricForge', 'ASRRuntime']) {
    nested = _p(outer, ['LyricForge', 'ASRRuntime']);
  }

  final Directory sandbox;
  final String support;
  final String outer;
  late final String nested;

  String get defaultRoot => _p(support, ['LyricForge', 'ASRRuntime']);

  File get pointer =>
      File(_p(support, ['LyricForge', 'asr-managed-storage.json']));

  Future<void> pointAt(String root) async {
    await pointer.parent.create(recursive: true);
    await pointer.writeAsString(
      jsonEncode({'schemaVersion': 2, 'managedRoot': root}),
    );
  }

  Future<String> pointedAt() async {
    final decoded = jsonDecode(await pointer.readAsString()) as Map;
    return decoded['managedRoot'] as String;
  }

  LocalAsrManagedStorageService service() => LocalAsrManagedStorageService(
    supportDirectoryResolver: () async => Directory(support),
    isMacOSResolver: () => false,
  );
}

void main() {
  late _Disk disk;

  setUp(() async {
    final sandbox = await Directory.systemTemp.createTemp('asr-leftovers-');
    disk = _Disk(sandbox);
    await Directory(disk.support).create(recursive: true);
  });

  tearDown(() async {
    if (await disk.sandbox.exists()) {
      await disk.sandbox.delete(recursive: true);
    }
  });

  group('inspect reports leftover copies', () {
    test('a clean environment has none', () async {
      await _write(disk.outer, _whisper, 'model');
      await disk.pointAt(disk.outer);

      final location = await disk.service().inspect();

      expect(location.activeRoot, Directory(disk.outer).absolute.path);
      expect(location.leftovers, isEmpty);
      expect(location.reclaimableBytes, 0);
    });

    test('a nested copy names what the active root still lacks', () async {
      await _write(disk.outer, _whisper, 'model');
      await _write(disk.outer, _health, '{}');
      await _write(disk.nested, _whisper, 'nested-model');
      await _write(disk.nested, _qwenMarker, '{}');
      await disk.pointAt(disk.outer);

      final location = await disk.service().inspect();

      final leftover = location.leftovers.single;
      expect(leftover.kind, AsrRuntimeLeftoverKind.nestedCopy);
      expect(leftover.path, Directory(disk.nested).absolute.path);
      expect(leftover.files, 2);
      expect(leftover.bytes, 'nested-model'.length + 2);
      expect(leftover.missingInActive, [AsrRuntimeUnit.qwenAsrLarge]);
      expect(leftover.mergesIntoActive, isTrue);
      expect(leftover.removable, isTrue);
      expect(location.reclaimableBytes, leftover.bytes);
    });

    test('a nested layout without files is reported as empty', () async {
      await _write(disk.outer, _whisper, 'model');
      await Directory(
        _p(disk.nested, ['models', 'whisper']),
      ).create(recursive: true);
      await Directory(_p(disk.nested, ['ffmpeg'])).create(recursive: true);
      await disk.pointAt(disk.outer);

      final leftover = (await disk.service().inspect()).leftovers.single;

      expect(leftover.isEmpty, isTrue);
      expect(leftover.missingInActive, isEmpty);
    });

    test('a pointer left on the nested copy is reported as such', () async {
      // The outer root is weaker, so resolveRoot keeps the nested pointer.
      await _write(disk.outer, _health, '{}');
      await _write(disk.nested, _whisper, 'nested-model');
      await _write(disk.nested, _bundleBin, 'bin');
      await disk.pointAt(disk.nested);

      final location = await disk.service().inspect();

      expect(location.activeRoot, Directory(disk.nested).absolute.path);
      final leftover = location.leftovers.single;
      expect(leftover.kind, AsrRuntimeLeftoverKind.activeIsNested);
      expect(leftover.missingInActive, [
        AsrRuntimeUnit.runtime,
        AsrRuntimeUnit.whisperModel,
      ]);
    });

    test('the default location is a copy once another root is used', () async {
      await _write(disk.outer, _whisper, 'model');
      await _write(disk.defaultRoot, _whisper, 'old-model');
      await disk.pointAt(disk.outer);

      final leftover = (await disk.service().inspect()).leftovers.single;

      expect(leftover.kind, AsrRuntimeLeftoverKind.defaultCopy);
      expect(leftover.path, Directory(disk.defaultRoot).absolute.path);
      expect(leftover.removable, isTrue);
    });

    test('a default copy with something the root lacks is kept', () async {
      await _write(disk.outer, _whisper, 'model');
      await _write(disk.defaultRoot, _qwenMarker, '{}');
      await disk.pointAt(disk.outer);

      final location = await disk.service().inspect();
      final leftover = location.leftovers.single;

      expect(leftover.missingInActive, [AsrRuntimeUnit.qwenAsrLarge]);
      expect(leftover.removable, isFalse);
      expect(location.reclaimableBytes, 0);
    });

    test('an empty default folder is not worth mentioning', () async {
      await _write(disk.outer, _whisper, 'model');
      await Directory(disk.defaultRoot).create(recursive: true);
      await disk.pointAt(disk.outer);

      expect((await disk.service().inspect()).leftovers, isEmpty);
    });

    test('a staging folder of a failed move is reported', () async {
      await _write(disk.outer, _whisper, 'model');
      final staging = _p(disk.outer, ['..', '.ASRRuntime.migrating-12345']);
      await _write(Directory(staging).absolute.path, [
        'models',
        'part',
      ], 'copy');
      await disk.pointAt(disk.outer);

      final leftovers = (await disk.service().inspect()).leftovers;

      expect(
        leftovers.map((leftover) => leftover.kind),
        contains(AsrRuntimeLeftoverKind.migrationStaging),
      );
    });
  });

  group('cleanUpLeftovers', () {
    test('a nested copy hands over what is missing and is removed', () async {
      await _write(disk.outer, _whisper, 'model');
      await _write(disk.nested, _whisper, 'nested-model');
      await _write(disk.nested, _qwenMarker, '{"sha":"x"}');
      await disk.pointAt(disk.outer);
      final service = disk.service();

      final result = await service.cleanUpLeftovers();

      expect(result.activeRoot, Directory(disk.outer).absolute.path);
      expect(result.movedUnits, [AsrRuntimeUnit.qwenAsrLarge]);
      expect(result.removedPaths, [Directory(disk.nested).absolute.path]);
      expect(result.freedBytes, 'nested-model'.length);
      expect(result.retainedPaths, isEmpty);
      expect(await _read(disk.outer, _qwenMarker), '{"sha":"x"}');
      expect(await _read(disk.outer, _whisper), 'model');
      expect(await Directory(disk.nested).exists(), isFalse);
      expect((await service.inspect()).leftovers, isEmpty);
      expect(service.isMoving, isFalse);
    });

    test('a pointer on the nested copy moves back to the outer root', () async {
      await _write(disk.outer, _health, '{}');
      await _write(disk.nested, _whisper, 'nested-model');
      await _write(disk.nested, _bundleBin, 'bin');
      await disk.pointAt(disk.nested);

      final result = await disk.service().cleanUpLeftovers();

      final outer = Directory(disk.outer).absolute.path;
      expect(result.activeRoot, outer);
      expect(await disk.pointedAt(), outer);
      expect(await _read(disk.outer, _whisper), 'nested-model');
      expect(await _read(disk.outer, _bundleBin), 'bin');
      expect(await Directory(disk.nested).exists(), isFalse);
      expect(result.movedUnits, [
        AsrRuntimeUnit.runtime,
        AsrRuntimeUnit.whisperModel,
      ]);
    });

    test(
      'the standalone Whisper of a nested copy is kept, not deleted',
      () async {
        await _write(disk.outer, _whisper, 'model');
        await _write(disk.nested, [
          'whisper',
          'v1.7.6',
          'whisper-cli.exe',
        ], 'b');
        await disk.pointAt(disk.outer);

        final result = await disk.service().cleanUpLeftovers();

        expect(result.movedUnits, [AsrRuntimeUnit.whisperRuntime]);
        expect(
          await _read(disk.outer, ['whisper', 'v1.7.6', 'whisper-cli.exe']),
          'b',
        );
        expect(await Directory(disk.nested).exists(), isFalse);
      },
    );

    test('a repeated chain is merged from the deepest copy up', () async {
      final deeper = _p(disk.nested, ['LyricForge', 'ASRRuntime']);
      await _write(disk.outer, _health, '{}');
      await _write(deeper, _whisper, 'deep-model');
      await _write(disk.nested, _qwenMarker, '{}');
      await disk.pointAt(disk.outer);

      final result = await disk.service().cleanUpLeftovers();

      expect(await _read(disk.outer, _whisper), 'deep-model');
      expect(await _read(disk.outer, _qwenMarker), '{}');
      expect(result.removedPaths, [Directory(disk.nested).absolute.path]);
    });

    test('a pure duplicate at the default location is removed', () async {
      await _write(disk.outer, _whisper, 'model');
      await _write(disk.defaultRoot, _whisper, 'old-model');
      await disk.pointAt(disk.outer);

      final result = await disk.service().cleanUpLeftovers();

      expect(result.removedPaths, [Directory(disk.defaultRoot).absolute.path]);
      expect(result.freedBytes, 'old-model'.length);
      expect(await Directory(disk.defaultRoot).exists(), isFalse);
      // The pointer beside it is not part of the copy.
      expect(await disk.pointer.exists(), isTrue);
    });

    test('a default copy with a unit the root lacks stays', () async {
      await _write(disk.outer, _whisper, 'model');
      await _write(disk.defaultRoot, _qwenMarker, '{}');
      await disk.pointAt(disk.outer);

      final result = await disk.service().cleanUpLeftovers();

      expect(result.removedPaths, isEmpty);
      expect(result.retainedPaths, [Directory(disk.defaultRoot).absolute.path]);
      expect(await _read(disk.defaultRoot, _qwenMarker), '{}');
    });

    test('staging folders of failed moves are removed', () async {
      await _write(disk.outer, _whisper, 'model');
      final staging = Directory(
        _p(disk.sandbox.path, [
          'Models',
          'LyricForge',
          '.ASRRuntime.migrating-1',
        ]),
      );
      await _write(staging.path, ['copy.bin'], 'copy');
      await disk.pointAt(disk.outer);

      final result = await disk.service().cleanUpLeftovers();

      expect(result.removedPaths, [staging.absolute.path]);
      expect(await staging.exists(), isFalse);
    });

    test('nothing to clean changes nothing', () async {
      await _write(disk.outer, _whisper, 'model');
      await disk.pointAt(disk.outer);

      final result = await disk.service().cleanUpLeftovers();

      expect(result.changed, isFalse);
      expect(result.retainedPaths, isEmpty);
      expect(await _read(disk.outer, _whisper), 'model');
    });
  });

  group('adopting an existing environment', () {
    test(
      'a scan keeps the root in use when another is no more complete',
      () async {
        // The root in use and the default location both have the runtime
        // and Whisper; the default one has more evidence files.
        await _write(disk.outer, _whisper, 'model');
        await _write(disk.outer, _bundleBin, 'bin');
        await _write(disk.defaultRoot, _whisper, 'model');
        await _write(disk.defaultRoot, _bundleBin, 'bin');
        await _write(disk.defaultRoot, _health, '{}');
        await _write(disk.defaultRoot, [
          'state',
          'qwen_rtx5080HighQuality.ready.json',
        ], '{}');
        await disk.pointAt(disk.outer);

        final result = await disk.service().discoverAndAdoptExisting();

        expect(result?.targetRoot, Directory(disk.outer).absolute.path);
        expect(
          result?.otherRoots,
          contains(Directory(disk.defaultRoot).absolute.path),
        );
        expect(await disk.pointedAt(), Directory(disk.outer).absolute.path);
      },
    );

    test('a scan moves to a root that is more complete', () async {
      await _write(disk.outer, _whisper, 'model');
      await _write(disk.defaultRoot, _whisper, 'model');
      await _write(disk.defaultRoot, _bundleBin, 'bin');
      await disk.pointAt(disk.outer);

      final result = await disk.service().discoverAndAdoptExisting();

      expect(result?.targetRoot, Directory(disk.defaultRoot).absolute.path);
    });

    test('adopting the outer root takes over the nested downloads', () async {
      await _write(disk.outer, _health, '{}');
      await _write(disk.nested, _whisper, 'nested-model');
      await disk.pointAt(disk.nested);

      final result = await disk.service().adoptExistingAt(disk.outer);

      expect(result.targetRoot, Directory(disk.outer).absolute.path);
      expect(result.adoptedExisting, isTrue);
      expect(result.movedUnits, [AsrRuntimeUnit.whisperModel]);
      expect(await _read(disk.outer, _whisper), 'nested-model');
      expect(await disk.pointedAt(), Directory(disk.outer).absolute.path);
    });

    test('re-adopting the root in use still lifts nested downloads', () async {
      await _write(disk.outer, _whisper, 'model');
      await _write(disk.nested, _qwenMarker, '{}');
      await disk.pointAt(disk.outer);

      final result = await disk.service().adoptExistingAt(disk.outer);

      expect(result.moved, isFalse);
      expect(result.movedUnits, [AsrRuntimeUnit.qwenAsrLarge]);
      expect(await _read(disk.outer, _qwenMarker), '{}');
    });
  });

  test('a move never copies into a folder inside another ASRRuntime', () async {
    final service = disk.service();
    final source = await service.resolveRoot();
    await _write(source.path, ['keep.bin'], 'keep');
    final foreign = _p(disk.sandbox.path, ['Other', 'ASRRuntime']);
    await _write(foreign, ['notes.txt'], 'mine');
    final inside = _p(foreign, ['sub']);
    await Directory(inside).create(recursive: true);

    await expectLater(
      service.moveToParent(inside),
      throwsA(
        isA<FileSystemException>().having(
          (error) => error.message,
          'message',
          contains('位于另一个 ASRRuntime 文件夹'),
        ),
      ),
    );

    expect((await service.resolveRoot()).path, source.path);
    expect(
      await Directory(_p(inside, ['LyricForge', 'ASRRuntime'])).exists(),
      isFalse,
    );
    expect(service.isMoving, isFalse);
  });
}
