import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/app/screen_assembly.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

ProjectManifest _project(List<LyricLine>? lines, {AudioAsset? audio}) =>
    ProjectManifest(
      id: 'p',
      name: '晴天',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      audioAsset: audio,
      lyricDocument: lines == null
          ? null
          : LyricDocument(language: 'zh', lines: lines),
    );

LyricLine _line(String text, {int confidence = 95, int startSeconds = 0}) =>
    LyricLine(
      text: text,
      startTime: Duration(seconds: startSeconds),
      endTime: Duration(seconds: startSeconds + 4),
      confidence: confidence,
    );

void main() {
  test('the project page counts what the editor lists (D-069)', () {
    final overview = countProjectLyricReview(
      _project([
        _line(''), // empty text: strong evidence, 必看
        _line('有点没把握', confidence: 40, startSeconds: 4), // 留意
        _line('月亮代表我的心', startSeconds: 8),
      ]),
    );

    expect(overview.suggested, 2);
    expect(overview.mustCheck, 1);
    expect(overview.reviewed, 0);
  });

  test('the audio length is used, as in the editor', () {
    final overview = countProjectLyricReview(
      _project(
        [_line('开头'), _line('超出音频', startSeconds: 8)],
        audio: const AudioAsset(
          originalPath: 'song.wav',
          format: 'wav',
          duration: Duration(seconds: 5),
        ),
      ),
    );

    expect(overview.suggested, 1);
  });

  test('a project without lyrics has nothing to review', () {
    final overview = countProjectLyricReview(_project(null));
    expect(overview.suggested, 0);
    expect(overview.mustCheck, 0);
  });
}
