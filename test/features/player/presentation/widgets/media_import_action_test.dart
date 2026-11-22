import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/media_import_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/media_import_action.dart';

void main() {
  group('mediaImportSummary', () {
    test('songs only', () {
      expect(
        mediaImportSummary(const MediaImportResult(importedPaths: ['a', 'b'])),
        '已导入 2 首歌曲',
      );
    });

    test('songs from videos are counted', () {
      expect(
        mediaImportSummary(
          const MediaImportResult(
            importedPaths: ['a', 'b'],
            extractedFromVideo: 1,
          ),
        ),
        '已导入 2 首歌曲（其中 1 个视频已提取为音频）',
      );
    });

    test('a single failure says why', () {
      expect(
        mediaImportSummary(
          const MediaImportResult(
            failures: [MediaImportFailure(name: 'a.mp4', reason: '这个视频没有声音')],
          ),
        ),
        '没有导入：这个视频没有声音',
      );
    });

    test('mixed results', () {
      expect(
        mediaImportSummary(
          const MediaImportResult(
            importedPaths: ['a'],
            failures: [MediaImportFailure(name: 'b.txt', reason: '不支持的文件格式')],
          ),
        ),
        '已导入 1 首歌曲，1 个文件没有导入',
      );
    });

    test('nothing usable', () {
      expect(mediaImportSummary(const MediaImportResult()), '没有选择可以导入的文件');
    });
  });
}
