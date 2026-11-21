import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../lyrics/domain/online/online_lyric_query.dart';
import '../../../lyrics/domain/online/song_lyrics_lookup.dart';
import '../../../lyrics/domain/services/lyric_file_import_service.dart';
import '../../../project/domain/models/lyric_timing.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/services/imported_lyrics_project.dart';
import 'lyrics_source_sheet.dart';
import 'paste_lyrics_dialog.dart';
import 'song_lyrics_preview_dialog.dart';

/// Lyrics the user chose for a song, with the `lyricSource` to record.
class AcquiredSongLyrics {
  final LyricImportResult result;
  final String source;

  const AcquiredSongLyrics({required this.result, required this.source});

  bool get timed => result.document.isTimed;
}

/// Runs one way of getting lyrics for a song and returns what the user kept.
///
/// [choice] decides the path: the online search with its timing preview, the
/// paste dialog, or a lyric file. Null means the user cancelled or nothing
/// usable came back; errors are shown here, so callers only save.
Future<AcquiredSongLyrics?> acquireSongLyrics(
  BuildContext context, {
  required LyricsSourceChoice choice,
  required LyricFileImportService importer,
  required OnlineLyricQuery query,
  SongLyricsLookup? lookup,
  SongLyricsPreviewPlayback? playback,
}) async {
  switch (choice) {
    case LyricsSourceChoice.online:
      if (lookup == null) return null;
      final picked = await showSongLyricsPreviewDialog(
        context,
        lookup: lookup,
        query: query,
        playback: playback,
      );
      if (picked == null) return null;
      return AcquiredSongLyrics(
        result: picked.result,
        source: onlineLyricsSource,
      );
    case LyricsSourceChoice.paste:
      final pasted = await showPasteLyricsDialog(
        context,
        importer: importer,
        songTitle: query.title,
      );
      if (pasted == null) return null;
      return AcquiredSongLyrics(result: pasted, source: pastedLyricsSource);
    case LyricsSourceChoice.file:
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: '导入歌词文件',
        type: FileType.custom,
        allowedExtensions: importer.supportedExtensions.toList()..sort(),
        allowMultiple: false,
      );
      final path = picked?.files.single.path;
      if (path == null || path.isEmpty) return null;
      try {
        final result = await importer.importFile(path);
        if (result.document.lines.isEmpty) {
          throw const LyricImportException('文件里没有可用的歌词行');
        }
        return AcquiredSongLyrics(result: result, source: 'imported-file');
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('歌词导入失败：$error')));
        }
        return null;
      }
  }
}

/// The message shown after lyrics were saved for a song.
String savedSongLyricsMessage(AcquiredSongLyrics lyrics) {
  if (!lyrics.timed) {
    return '已保存参考歌词（无时间轴）：播放时静态显示、手动滚动；需要同步或 KTV 时再打轴';
  }
  final words = lyrics.result.wordTimedRows;
  return words > 0
      ? '已保存带时间轴的歌词（$words 行带逐字时间）'
      : '已保存带时间轴的歌词，可以直接播放或进入 KTV';
}

/// Asks where the lyrics should come from, gets them and saves them on
/// [project]. Returns the saved project, or null when nothing changed.
///
/// Used by the project player for a project without lyrics or with
/// reference lyrics only; the replaced document is kept as a backup.
Future<ProjectManifest?> addLyricsToProject(
  BuildContext context, {
  required ProjectManifest project,
  required ProjectRepository repository,
  required LyricFileImportService importer,
  SongLyricsLookup? lookup,
  SongLyricsPreviewPlayback? playback,
  LyricsSourceChoice? choice,
}) async {
  final audioAsset = project.audioAsset;
  if (audioAsset == null) return null;
  final selected =
      choice ??
      await showLyricsSourceSheet(
        context,
        onlineAvailable: lookup != null,
        songTitle: project.name,
      );
  if (selected == null || !context.mounted) return null;
  final lyrics = await acquireSongLyrics(
    context,
    choice: selected,
    importer: importer,
    lookup: lookup,
    playback: playback,
    query: OnlineLyricQuery.fromProject(
      name: project.name,
      artist: project.artist,
      duration: audioAsset.duration,
    ),
  );
  if (lyrics == null) return null;

  final ProjectManifest saved;
  try {
    saved = await repository.updateProject(
      projectWithImportedLyrics(
        project,
        title: project.name,
        artist: project.artist,
        audioAsset: audioAsset,
        artworkPath: null,
        result: lyrics.result,
        now: DateTime.now(),
        source: lyrics.source,
      ),
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('歌词保存失败：$error')));
    }
    return null;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(savedSongLyricsMessage(lyrics))));
  }
  return saved;
}
