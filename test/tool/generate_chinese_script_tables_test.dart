import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/text/chinese_script_data.g.dart'
    as data;

/// OpenCC revision the committed tables were generated from.
const String _openccRevision = 'fae2a0a911c30764e669a7d8b0591cd8e852934a';
const String _committedPath =
    'lib/features/lyrics/domain/text/chinese_script_data.g.dart';

void main() {
  test('the data revision names the pinned OpenCC commit', () {
    expect(
      data.chineseScriptDataRevision,
      'opencc-${_openccRevision.substring(0, 12)}-lyricforge-1',
    );
    final header = File(_committedPath).readAsLinesSync().take(12).join('\n');
    expect(header, contains('revision $_openccRevision.'));
    expect(header, contains('third_party/opencc/LICENSE'));
    expect(File('third_party/opencc/LICENSE').existsSync(), isTrue);
  });

  // Regeneration needs an OpenCC checkout, which the test suite does not
  // download. Point OPENCC_DIR at a checkout of the pinned revision to prove
  // the committed tables are exactly what the generator writes.
  final openccDir = Platform.environment['OPENCC_DIR'];
  test(
    'the generator reproduces the committed tables',
    () async {
      final temp = await Directory.systemTemp.createTemp('opencc-tables-');
      addTearDown(() => temp.delete(recursive: true));
      final output = '${temp.path}/chinese_script_data.g.dart';
      final result = await Process.run('dart', [
        'run',
        'tool/generate_chinese_script_tables.dart',
        '--opencc',
        openccDir!,
        '--revision',
        _openccRevision,
        '--output',
        output,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final generated = File(output).readAsLinesSync();
      final committed = File(_committedPath).readAsLinesSync();
      for (var index = 0; index < generated.length; index++) {
        if (index >= committed.length || generated[index] != committed[index]) {
          fail(
            'Line ${index + 1} differs. Generated: '
            '${generated[index]}\nCommitted: '
            '${index < committed.length ? committed[index] : '<end>'}',
          );
        }
      }
      expect(generated.length, committed.length);
      expect(
        File(output).readAsStringSync(),
        File(_committedPath).readAsStringSync(),
      );
    },
    skip: openccDir == null || openccDir.isEmpty
        ? 'Set OPENCC_DIR to an OpenCC checkout at $_openccRevision.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
