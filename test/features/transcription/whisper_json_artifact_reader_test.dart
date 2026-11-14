import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/whisper_json_artifact_reader.dart';

String response({String text = 'hello', int from = 0, int to = 1000}) =>
    jsonEncode({
      'result': {'language': 'en'},
      'transcription': [
        {
          'text': text,
          'offsets': {'from': from, 'to': to},
          'tokens': [
            {'text': text, 'p': 0.9},
          ],
        },
      ],
    });

void main() {
  late Directory root;
  late WhisperJsonArtifactReader reader;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('whisper-json-artifacts-');
    reader = const WhisperJsonArtifactReader();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('missing and malformed metadata paths fail closed', () async {
    expect(
      (await reader.read(null)).status,
      WhisperJsonArtifactStatus.noPath,
    );
    expect(
      (await reader.read(42)).status,
      WhisperJsonArtifactStatus.invalidPath,
    );
    expect(
      (await reader.read('  ')).status,
      WhisperJsonArtifactStatus.invalidPath,
    );
    expect(
      (await reader.read('bad\u0000path')).status,
      WhisperJsonArtifactStatus.invalidPath,
    );
    final overlongPath = List.filled(
      WhisperJsonArtifactReader.maxPathCharacters + 1,
      'x',
    ).join();
    final overlongResult = await reader.read(overlongPath);
    expect(overlongResult.status, WhisperJsonArtifactStatus.invalidPath);
    expect(
      (await reader.read('${root.path}/missing.json')).status,
      WhisperJsonArtifactStatus.missing,
    );
  });

  test('reads a regular JSON artifact into a bounded transcript', () async {
    final file = File('${root.path}/whisper.json');
    await file.writeAsString(response(text: 'hello 🌙', to: 2400));

    final result = await reader.read(file.path);

    expect(result.status, WhisperJsonArtifactStatus.loaded);
    expect(result.isLoaded, isTrue);
    expect(result.parsed!.detectedLanguage, 'en');
    expect(result.parsed!.document.lines.single.text, 'hello 🌙');
    expect(result.parsed!.document.lines.single.endTime.inMilliseconds, 2400);
    expect(result.parsed!.document.metadata['rawJsonPath'], file.path);
  });

  test(
    'rejects directories, empty files, oversized and invalid-UTF8 files',
    () async {
      expect(
        (await reader.read(root.path)).status,
        WhisperJsonArtifactStatus.notRegularFile,
      );

      final empty = File('${root.path}/empty.json');
      await empty.create();
      expect(
        (await reader.read(empty.path)).status,
        WhisperJsonArtifactStatus.empty,
      );

      final tooLarge = File('${root.path}/large.json');
      await tooLarge.writeAsString(response());
      expect(
        (await const WhisperJsonArtifactReader(maxArtifactBytes: 2).read(
          tooLarge.path,
        )).status,
        WhisperJsonArtifactStatus.tooLarge,
      );

      final invalidUtf8 = File('${root.path}/invalid-utf8.json');
      await invalidUtf8.writeAsBytes([0xff, 0xfe, 0xfd]);
      expect(
        (await reader.read(invalidUtf8.path)).status,
        WhisperJsonArtifactStatus.invalidEncoding,
      );
    },
  );

  test(
    'distinguishes invalid JSON from JSON without usable lyric rows',
    () async {
      final invalid = File('${root.path}/invalid.json');
      await invalid.writeAsString('{not json');
      expect(
        (await reader.read(invalid.path)).status,
        WhisperJsonArtifactStatus.invalidJson,
      );

      final noRows = File('${root.path}/no-rows.json');
      await noRows.writeAsString(
        jsonEncode({
          'result': {'language': 'en'},
          'transcription': [
            {
              'text': '   ',
              'offsets': {'from': 0, 'to': 1000},
            },
          ],
        }),
      );
      expect(
        (await reader.read(noRows.path)).status,
        WhisperJsonArtifactStatus.noUsableSegments,
      );
    },
  );

  test('does not follow a symbolic link to an arbitrary file', () async {
    final target = File('${root.path}/target.json');
    await target.writeAsString(response());
    final link = Link('${root.path}/linked.json');
    await link.create(target.path);

    expect(
      (await reader.read(link.path)).status,
      WhisperJsonArtifactStatus.notRegularFile,
    );
  });
}
