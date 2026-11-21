import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_managed_storage_service.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/asr_leftover_text.dart';

// Widget tests run as a non-Windows platform, so folders use `/`.
const _outer = '/data/Models/LyricForge/ASRRuntime';
const _nested = '$_outer/LyricForge/ASRRuntime';

AsrManagedStorageMoveResult _adopted({
  List<AsrRuntimeUnit> movedUnits = const [],
  List<String> otherRoots = const [],
}) {
  return AsrManagedStorageMoveResult(
    sourceRoot: _nested,
    targetRoot: _outer,
    copiedBytes: 0,
    copiedFiles: 0,
    moved: true,
    adoptedExisting: true,
    movedUnits: movedUnits,
    otherRoots: otherRoots,
  );
}

AsrManagedStorageLocation _location(List<AsrRuntimeLeftover> leftovers) {
  return AsrManagedStorageLocation(
    activeRoot: _outer,
    defaultRoot: '/support/LyricForge/ASRRuntime',
    managedBytes: 0,
    isDefault: false,
    leftovers: leftovers,
  );
}

void main() {
  group('units', () {
    test('every unit has a name', () {
      for (final unit in AsrRuntimeUnit.values) {
        expect(AsrLeftoverText.unitLabel(unit), isNotEmpty);
      }
      expect(
        AsrRuntimeUnit.values.map(AsrLeftoverText.unitLabel).toSet(),
        hasLength(AsrRuntimeUnit.values.length),
      );
    });

    test('a list is joined with the Chinese enumeration comma', () {
      expect(
        AsrLeftoverText.unitList([
          AsrRuntimeUnit.ffmpeg,
          AsrRuntimeUnit.whisperModel,
        ]),
        'FFmpeg、Whisper large-v3 模型',
      );
    });
  });

  group('adoption note', () {
    test('nothing to add when only the pointer moved', () {
      expect(AsrLeftoverText.adoptionNote(_adopted()), isEmpty);
      expect(AsrLeftoverText.withAdoptionNote('已启用。', _adopted()), '已启用。');
    });

    test('moved components are named and said not to be downloaded', () {
      final note = AsrLeftoverText.adoptionNote(
        _adopted(movedUnits: [AsrRuntimeUnit.whisperModel]),
      );
      expect(note, contains('Whisper large-v3 模型'));
      expect(note, contains('没有复制或重新下载'));
    });

    test('other environments found are listed as untouched', () {
      final note = AsrLeftoverText.adoptionNote(
        _adopted(otherRoots: ['/a/ASRRuntime', '/b/ASRRuntime']),
      );
      expect(note, contains('/a/ASRRuntime、/b/ASRRuntime'));
      expect(note, contains('未使用、未改动'));
    });

    test('the note follows the message', () {
      final message = AsrLeftoverText.withAdoptionNote(
        '已启用。',
        _adopted(movedUnits: [AsrRuntimeUnit.runtime]),
      );
      expect(message, startsWith('已启用。'));
      expect(message, contains('识别程序'));
    });
  });

  group('leftovers', () {
    test('the title gives what cleaning frees', () {
      final location = _location(const [
        AsrRuntimeLeftover(
          path: _nested,
          kind: AsrRuntimeLeftoverKind.nestedCopy,
          bytes: 3 << 30,
          files: 3,
        ),
      ]);
      expect(AsrLeftoverText.title(location), contains('3.00 GB'));
    });

    test('a title without anything to free says only what was found', () {
      final location = _location(const [
        AsrRuntimeLeftover(
          path: _nested,
          kind: AsrRuntimeLeftoverKind.nestedCopy,
          bytes: 0,
          files: 0,
        ),
      ]);
      expect(AsrLeftoverText.title(location), '发现重复的识别环境文件夹');
    });

    test('a nested copy says what it will hand over', () {
      final line = AsrLeftoverText.line(
        const AsrRuntimeLeftover(
          path: _nested,
          kind: AsrRuntimeLeftoverKind.nestedCopy,
          bytes: 1 << 30,
          files: 4,
          missingInActive: [AsrRuntimeUnit.qwenAsrLarge],
        ),
      );
      expect(line, contains(_nested));
      expect(line, contains('1.00 GB'));
      expect(line, contains('旧版本误建'));
      expect(line, contains('Qwen3-ASR 1.7B 模型当前环境还没有'));
      expect(line, contains('不会重新下载'));
    });

    test('a nested copy with nothing new can simply go', () {
      final line = AsrLeftoverText.line(
        const AsrRuntimeLeftover(
          path: _nested,
          kind: AsrRuntimeLeftoverKind.nestedCopy,
          bytes: 1 << 20,
          files: 1,
        ),
      );
      expect(line, contains('可以直接删除'));
    });

    test('an empty layout is called empty folders', () {
      final line = AsrLeftoverText.line(
        const AsrRuntimeLeftover(
          path: _nested,
          kind: AsrRuntimeLeftoverKind.nestedCopy,
          bytes: 0,
          files: 0,
        ),
      );
      expect(line, contains('只有空文件夹'));
    });

    test('a nested root in use names the outer root it returns to', () {
      final line = AsrLeftoverText.line(
        const AsrRuntimeLeftover(
          path: _nested,
          kind: AsrRuntimeLeftoverKind.activeIsNested,
          bytes: 1 << 30,
          files: 4,
        ),
      );
      expect(line, contains('当前正在使用内层重复的文件夹'));
      expect(line, contains('移回外层 $_outer '));
    });

    test('a default copy says whether it can go', () {
      const path = '/support/LyricForge/ASRRuntime';
      final duplicate = AsrLeftoverText.line(
        const AsrRuntimeLeftover(
          path: path,
          kind: AsrRuntimeLeftoverKind.defaultCopy,
          bytes: 1 << 30,
          files: 2,
        ),
      );
      expect(duplicate, contains('可以删除'));

      final unique = AsrLeftoverText.line(
        const AsrRuntimeLeftover(
          path: path,
          kind: AsrRuntimeLeftoverKind.defaultCopy,
          bytes: 1 << 30,
          files: 2,
          missingInActive: [AsrRuntimeUnit.forcedAligner],
        ),
      );
      expect(unique, contains('会保留这个文件夹'));
      expect(unique, contains('Qwen3 强制对齐模型'));
    });

    test('a staging folder can go', () {
      final line = AsrLeftoverText.line(
        const AsrRuntimeLeftover(
          path: '/data/Models/LyricForge/.ASRRuntime.migrating-1',
          kind: AsrRuntimeLeftoverKind.migrationStaging,
          bytes: 1 << 20,
          files: 1,
        ),
      );
      expect(line, contains('迁移中断留下的暂存文件夹'));
    });

    test('the outer folder drops the nested suffix in any case', () {
      expect(AsrLeftoverText.outerOf(_nested), _outer);
      expect(AsrLeftoverText.outerOf('$_nested/'), _outer);
      expect(AsrLeftoverText.outerOf('$_outer/lyricforge/asrruntime'), _outer);
      expect(AsrLeftoverText.outerOf('/elsewhere'), '/elsewhere');
    });

    test('the confirmation lists every leftover and what happens', () {
      final location = _location(const [
        AsrRuntimeLeftover(
          path: _nested,
          kind: AsrRuntimeLeftoverKind.nestedCopy,
          bytes: 1 << 30,
          files: 2,
        ),
        AsrRuntimeLeftover(
          path: '/support/LyricForge/ASRRuntime',
          kind: AsrRuntimeLeftoverKind.defaultCopy,
          bytes: 1 << 30,
          files: 2,
        ),
      ]);
      final text = AsrLeftoverText.confirmation(location);
      expect('•'.allMatches(text), hasLength(2));
      expect(text, contains('同一磁盘内移过来'));
      expect(text, contains('不能开始识别或下载'));
    });
  });

  group('clean-up result', () {
    test('moved, removed and freed are all reported', () {
      final text = AsrLeftoverText.cleanedUp(
        const AsrRuntimeCleanupResult(
          activeRoot: _outer,
          movedUnits: [AsrRuntimeUnit.whisperModel],
          removedPaths: [_nested],
          freedBytes: 2 << 30,
        ),
      );
      expect(text, contains('已把Whisper large-v3 模型移入当前环境'));
      expect(text, contains('删除了 1 个重复文件夹'));
      expect(text, contains('2.00 GB'));
      expect(text, contains('当前环境：$_outer'));
    });

    test('kept folders are listed with the reason', () {
      final text = AsrLeftoverText.cleanedUp(
        const AsrRuntimeCleanupResult(
          activeRoot: _outer,
          retainedPaths: ['/support/LyricForge/ASRRuntime'],
        ),
      );
      expect(text, contains('以下文件夹已保留'));
      expect(text, contains('/support/LyricForge/ASRRuntime'));
    });

    test('nothing to do says so', () {
      expect(
        AsrLeftoverText.cleanedUp(
          const AsrRuntimeCleanupResult(activeRoot: _outer),
        ),
        '没有需要清理的重复文件夹。',
      );
    });

    test('a failure names the error', () {
      expect(AsrLeftoverText.cleanupFailed('locked'), contains('locked'));
    });
  });
}
