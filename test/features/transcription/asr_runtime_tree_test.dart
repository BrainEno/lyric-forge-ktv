import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_runtime_tree.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/asr_runtime_leftovers.dart';

final _sep = Platform.pathSeparator;

String _p(Directory root, List<String> parts) => asrJoinPath(root.path, parts);

Future<File> _write(Directory root, List<String> parts, String content) async {
  final file = File(_p(root, parts));
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
  return file;
}

Future<String?> _read(Directory root, List<String> parts) async {
  final file = File(_p(root, parts));
  return await file.exists() ? file.readAsString() : null;
}

const _bundleBin = ['bundle', 'bin', 'qwen3-asr.exe'];
const _ffmpeg = ['ffmpeg', 'bin', 'ffmpeg.exe'];
const _whisper = ['models', 'whisper', 'ggml-large-v3.bin'];
const _whisperPart = ['models', 'whisper', 'ggml-large-v3.bin.part'];
const _revision = ['state', 'runtime-build-revision.txt'];
const _health = ['.runtime-health-v1.json'];
const _qwenLarge = ['models', 'qwen', 'Qwen--Qwen3-ASR-1.7B'];

void main() {
  late Directory sandbox;
  late Directory outer;
  late Directory nested;
  const merger = AsrRuntimeTreeMerger();

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('asr-runtime-tree-');
    outer = Directory('${sandbox.path}${_sep}ASRRuntime');
    nested = Directory('${outer.path}${_sep}LyricForge${_sep}ASRRuntime');
    await nested.create(recursive: true);
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  group('AsrRuntimeTree', () {
    test('an empty folder has no complete unit', () async {
      expect(await AsrRuntimeTree(outer).completeUnits(), isEmpty);
    });

    test('a folder that does not exist has no complete unit', () async {
      final missing = Directory('${sandbox.path}${_sep}missing');
      expect(await AsrRuntimeTree(missing).completeUnits(), isEmpty);
    });

    test('each unit is recognised by the file the managers look for', () async {
      await _write(outer, _bundleBin, 'bin');
      await _write(outer, _ffmpeg, 'ffmpeg');
      await _write(outer, _whisper, 'model');
      await _write(outer, [..._qwenLarge, '.lyricforge-model.json'], '{}');
      await _write(outer, [
        'models',
        'qwen',
        'Qwen--Qwen3-ForcedAligner-0.6B',
        '.lyricforge-model.json',
      ], '{}');

      expect(await AsrRuntimeTree(outer).completeUnits(), {
        AsrRuntimeUnit.runtime,
        AsrRuntimeUnit.ffmpeg,
        AsrRuntimeUnit.whisperModel,
        AsrRuntimeUnit.qwenAsrLarge,
        AsrRuntimeUnit.forcedAligner,
      });
    });

    test('whisper-cli alone also makes the runtime complete', () async {
      await _write(outer, ['bundle', 'bin', 'whisper-cli'], 'bin');
      expect(
        await AsrRuntimeTree(outer).isComplete(AsrRuntimeUnit.runtime),
        isTrue,
      );
    });

    test('the standalone Whisper is found below its release folder', () async {
      final tree = AsrRuntimeTree(outer);
      await _write(outer, ['whisper', 'v1.7.6', 'README.md'], 'docs');
      expect(await tree.isComplete(AsrRuntimeUnit.whisperRuntime), isFalse);
      expect(await tree.hasAny(AsrRuntimeUnit.whisperRuntime), isTrue);

      await _write(outer, [
        'whisper',
        'v1.7.6',
        'Release',
        'Whisper-CLI.exe',
      ], 'bin');
      expect(await tree.isComplete(AsrRuntimeUnit.whisperRuntime), isTrue);
    });

    test('a Qwen model without the marker needs config and weights', () async {
      await _write(nested, [..._qwenLarge, 'config.json'], '{}');
      final tree = AsrRuntimeTree(nested);
      expect(await tree.isComplete(AsrRuntimeUnit.qwenAsrLarge), isFalse);

      await _write(nested, [..._qwenLarge, 'model.safetensors'], 'w');
      expect(await tree.isComplete(AsrRuntimeUnit.qwenAsrLarge), isTrue);
    });

    test('a partial download is something but not complete', () async {
      await _write(outer, _whisperPart, 'half');
      final tree = AsrRuntimeTree(outer);
      expect(await tree.isComplete(AsrRuntimeUnit.whisperModel), isFalse);
      expect(await tree.hasAny(AsrRuntimeUnit.whisperModel), isTrue);
      expect(await tree.hasAny(AsrRuntimeUnit.ffmpeg), isFalse);
    });

    test(
      'the runtime pieces include readiness markers of both copies',
      () async {
        await _write(outer, [
          'state',
          'qwen_rtx5080HighQuality.ready.json',
        ], '');
        await _write(nested, [
          'state',
          'qwen_intelMacHighQuality.ready.json',
        ], '');
        await _write(nested, ['state', 'unrelated.json'], '');

        final pieces = await AsrRuntimeTree(
          nested,
        ).pieces(AsrRuntimeUnit.runtime, other: AsrRuntimeTree(outer));

        expect(pieces, [
          ['bundle'],
          _revision,
          _health,
          ['state', 'qwen_intelMacHighQuality.ready.json'],
          ['state', 'qwen_rtx5080HighQuality.ready.json'],
        ]);
      },
    );

    test('the runtime revision is read with its time', () async {
      expect(await AsrRuntimeTree(outer).runtimeRevision(), isNull);
      await _write(outer, _revision, ' r42 \n');
      final revision = await AsrRuntimeTree(outer).runtimeRevision();
      expect(revision?.revision, 'r42');
    });
  });

  group('AsrRuntimeTreeMerger', () {
    test('a unit the target lacks moves in without copying', () async {
      await _write(nested, _whisper, 'nested-model');

      final outcome = await merger.merge(from: nested, into: outer);

      expect(outcome.movedUnits, [AsrRuntimeUnit.whisperModel]);
      expect(outcome.failures, isEmpty);
      expect(await _read(outer, _whisper), 'nested-model');
      expect(await _read(nested, _whisper), isNull);
    });

    test('the standalone Whisper moves as one folder', () async {
      await _write(nested, ['whisper', 'v1.7.6', 'whisper-cli.exe'], 'bin');
      await _write(nested, ['whisper', 'v1.7.6', 'whisper.dll'], 'dll');

      final outcome = await merger.merge(from: nested, into: outer);

      expect(outcome.movedUnits, [AsrRuntimeUnit.whisperRuntime]);
      expect(await _read(outer, ['whisper', 'v1.7.6', 'whisper.dll']), 'dll');
      expect(await Directory(_p(nested, ['whisper'])).exists(), isFalse);
    });

    test('a unit complete in both stays as the target has it', () async {
      await _write(outer, _whisper, 'outer-model');
      await _write(nested, _whisper, 'nested-model');

      final outcome = await merger.merge(from: nested, into: outer);

      expect(outcome.movedUnits, isEmpty);
      expect(await _read(outer, _whisper), 'outer-model');
      expect(await _read(nested, _whisper), 'nested-model');
    });

    test(
      'a partial piece of the target makes way for a complete one',
      () async {
        await _write(outer, _whisperPart, 'outer-half');
        await _write(nested, _whisper, 'nested-model');

        await merger.merge(from: nested, into: outer);

        expect(await _read(outer, _whisper), 'nested-model');
        expect(await _read(outer, _whisperPart), isNull);
        // Nothing is deleted: the partial file now sits in the leftover copy.
        expect(await _read(nested, _whisperPart), 'outer-half');
      },
    );

    test('a complete runtime moves in as a whole with its state', () async {
      await _write(nested, _bundleBin, 'bin');
      await _write(nested, ['bundle', 'lib', 'cuda.dll'], 'dll');
      await _write(nested, _revision, 'r2');
      await _write(nested, _health, '{"ok":true}');
      await _write(nested, ['state', 'qwen_rtx5080HighQuality.ready.json'], '');
      await _write(outer, _health, '{"stale":true}');

      final outcome = await merger.merge(from: nested, into: outer);

      expect(outcome.movedUnits, [AsrRuntimeUnit.runtime]);
      expect(await _read(outer, _bundleBin), 'bin');
      expect(await _read(outer, ['bundle', 'lib', 'cuda.dll']), 'dll');
      expect(await _read(outer, _revision), 'r2');
      expect(await _read(outer, _health), '{"ok":true}');
      expect(
        await _read(outer, ['state', 'qwen_rtx5080HighQuality.ready.json']),
        '',
      );
      // The outer health record described no bundle; it moves out with it.
      expect(await _read(nested, _health), '{"stale":true}');
    });

    test('a runtime from a later build replaces an older one', () async {
      await _write(outer, _bundleBin, 'old-bin');
      final oldRevision = await _write(outer, _revision, 'r1');
      await oldRevision.setLastModified(DateTime(2026, 10, 1));
      await _write(nested, _bundleBin, 'new-bin');
      final newRevision = await _write(nested, _revision, 'r2');
      await newRevision.setLastModified(DateTime(2026, 11, 1));

      final outcome = await merger.merge(from: nested, into: outer);

      expect(outcome.movedUnits, [AsrRuntimeUnit.runtime]);
      expect(await _read(outer, _bundleBin), 'new-bin');
      expect(await _read(outer, _revision), 'r2');
      expect(await _read(nested, _bundleBin), 'old-bin');
      expect(await _read(nested, _revision), 'r1');
    });

    test('an older or identical runtime does not replace the target', () async {
      await _write(outer, _bundleBin, 'outer-bin');
      final outerRevision = await _write(outer, _revision, 'r2');
      await outerRevision.setLastModified(DateTime(2026, 11, 1));
      await _write(nested, _bundleBin, 'nested-bin');
      final nestedRevision = await _write(nested, _revision, 'r1');
      await nestedRevision.setLastModified(DateTime(2026, 10, 1));

      expect(
        (await merger.merge(from: nested, into: outer)).movedUnits,
        isEmpty,
      );
      expect(await _read(outer, _bundleBin), 'outer-bin');

      await nestedRevision.writeAsString('r2');
      await nestedRevision.setLastModified(DateTime(2026, 12, 1));
      expect(
        (await merger.merge(from: nested, into: outer)).movedUnits,
        isEmpty,
      );
      expect(await _read(outer, _bundleBin), 'outer-bin');
    });

    test('a runtime without a revision never replaces one with it', () async {
      await _write(outer, _bundleBin, 'outer-bin');
      await _write(outer, _revision, 'r1');
      await _write(nested, _bundleBin, 'nested-bin');

      expect(
        (await merger.merge(from: nested, into: outer)).movedUnits,
        isEmpty,
      );
      expect(await _read(outer, _bundleBin), 'outer-bin');
    });

    test('partial pieces move in only where the target has nothing', () async {
      await _write(nested, [..._qwenLarge, 'model.safetensors.part'], 'half');
      await _write(nested, _whisperPart, 'nested-half');
      await _write(outer, _whisperPart, 'outer-half');

      final outcome = await merger.merge(from: nested, into: outer);

      // Resumable, but not complete, so not reported as reused.
      expect(outcome.movedUnits, isEmpty);
      expect(
        await _read(outer, [..._qwenLarge, 'model.safetensors.part']),
        'half',
      );
      expect(await _read(outer, _whisperPart), 'outer-half');
      expect(await _read(nested, _whisperPart), 'nested-half');
    });

    test('resumable downloads move unless the target has the same', () async {
      await _write(nested, ['downloads', 'asr-runtime.zip.part'], 'nested');
      await _write(nested, ['downloads', 'ffmpeg.zip.part'], 'ffmpeg');
      await _write(nested, ['downloads', 'asr-runtime.zip'], 'finished');
      await _write(outer, ['downloads', 'asr-runtime.zip.part'], 'outer');

      await merger.merge(from: nested, into: outer);

      expect(
        await _read(outer, ['downloads', 'asr-runtime.zip.part']),
        'outer',
      );
      expect(await _read(outer, ['downloads', 'ffmpeg.zip.part']), 'ffmpeg');
      expect(await _read(outer, ['downloads', 'asr-runtime.zip']), isNull);
      expect(
        await _read(nested, ['downloads', 'asr-runtime.zip.part']),
        'nested',
      );
    });

    test('every unit is handled in one pass', () async {
      await _write(nested, _bundleBin, 'bin');
      await _write(nested, _ffmpeg, 'ffmpeg');
      await _write(nested, _whisper, 'model');
      await _write(nested, [..._qwenLarge, '.lyricforge-model.json'], '{}');

      final outcome = await merger.merge(from: nested, into: outer);

      expect(outcome.movedUnits, [
        AsrRuntimeUnit.runtime,
        AsrRuntimeUnit.ffmpeg,
        AsrRuntimeUnit.whisperModel,
        AsrRuntimeUnit.qwenAsrLarge,
      ]);
      expect(await AsrRuntimeTree(nested).completeUnits(), isEmpty);
    });

    test('no holding folder is left behind', () async {
      await _write(outer, _whisperPart, 'outer-half');
      await _write(nested, _whisper, 'nested-model');
      await _write(outer, _health, '{}');
      await _write(nested, _health, '{}');
      await _write(nested, _bundleBin, 'bin');

      await merger.merge(from: nested, into: outer);

      final names = await outer
          .list()
          .map(
            (entity) => entity.uri.pathSegments.where((s) => s.isNotEmpty).last,
          )
          .toList();
      expect(
        names.where((name) => name.startsWith('.lyricforge-merge-')),
        isEmpty,
      );
    });

    test('a missing source changes nothing', () async {
      final missing = Directory('${sandbox.path}${_sep}gone');
      final outcome = await merger.merge(from: missing, into: outer);
      expect(outcome.movedUnits, isEmpty);
      expect(outcome.failures, isEmpty);
    });
  });
}
