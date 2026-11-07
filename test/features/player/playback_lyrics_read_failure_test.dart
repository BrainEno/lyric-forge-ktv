import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/player/data/services/file_audio_path_canonicalizer.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_path_canonicalizer.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_lyrics_availability.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/local_library_dependencies.dart';
import 'package:lyric_forge_ktv/features/player/presentation/playback_screen_dependencies.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/local_song_lyrics_import_action.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/now_playing_lyrics_project_action.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/file_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';

const _path = '/music/song.mp3';
const _item = PlaybackItem(
  id: 'song', title: 'Song', hasLyrics: true,
  audioAsset: AudioAsset(originalPath: _path, format: 'mp3'),
);

ProjectManifest _project(String id) => ProjectManifest(
  id: id, name: id, createdAt: DateTime(2026), updatedAt: DateTime(2026),
  audioAsset: const AudioAsset(originalPath: _path, format: 'mp3'),
  lyricDocument: const LyricDocument(language: 'en', lines: [
    LyricLine(text: 'hello', startTime: Duration.zero, endTime: Duration(seconds: 1)),
  ]),
);

LocalMediaMetadata _linked() => LocalMediaMetadata(
  sourcePath: _path, updatedAt: DateTime(2026),
  metadata: const {'linkedProjectId': 'linked', 'hasLyrics': true, 'custom': 'keep'},
);

PlaybackLyricsResolver _resolver(_Projects projects, _Metadata metadata, _Session session, {AudioPathCanonicalizer pathCanonicalizer = const FileAudioPathCanonicalizer()}) =>
    PlaybackLyricsResolver(projectRepository: projects, metadataRepository: metadata,
      playbackSession: session, pathCanonicalizer: pathCanonicalizer);

void main() {
  test('linked project lookup error never replaces link with fallback; retry recovers', () async {
    final metadata = _Metadata(_linked());
    final projects = _Projects([_project('linked'), _project('other')])..failGet = true;
    final session = _Session();
    final resolver = _resolver(projects, metadata, session);
    await expectLater(resolver.resolveAndSync(_item), throwsStateError);
    expect(projects.scans, 0);
    expect(metadata.saves, isEmpty);
    expect(session.updates, isEmpty);
    projects.failGet = false;
    final recovered = await resolver.resolveAndSync(_item);
    expect(recovered.projectId, 'linked');
    expect(recovered.hasLyrics, isTrue);
    expect(metadata.saves, isEmpty);
    expect(session.updates, isEmpty);
  });

  test('scan error does not clear link; confirmed missing project still heals', () async {
    final metadata = _Metadata(_linked());
    final projects = _Projects([])..failScan = true;
    final session = _Session();
    final resolver = _resolver(projects, metadata, session);
    await expectLater(resolver.resolveAndSync(_item), throwsStateError);
    expect(metadata.saves, isEmpty);
    expect(session.updates, isEmpty);
    projects.failScan = false;
    final resolved = await resolver.resolveAndSync(_item);
    expect(resolved.clearedLink, isTrue);
    expect(metadata.saves.single.metadata, {'custom': 'keep'});
    expect(session.updates.single.hasLyrics, isFalse);
  });

  test('metadata read error does not overwrite metadata or consult fallback', () async {
    final metadata = _Metadata(_linked())..failReadAt = 1;
    final projects = _Projects([_project('other')]);
    final session = _Session();
    await expectLater(_resolver(projects, metadata, session).resolveAndSync(_item), throwsStateError);
    expect(projects.scans, 0);
    expect(metadata.saves, isEmpty);
    expect(session.updates, isEmpty);
  });

  test('direct project lookup and path errors do not change the queue or link', () async {
    final metadata = _Metadata(_linked());
    final projects = _Projects([])..failGet = true;
    final session = _Session();
    await expectLater(_resolver(projects, metadata, session).resolveAndSync(
      _item.copyWith(projectId: 'direct'),
    ), throwsStateError);
    expect(metadata.reads, 0);
    expect(session.updates, isEmpty);
    projects.failGet = false;
    await expectLater(_resolver(projects, metadata, session, pathCanonicalizer: _FailingPaths()).resolveAndSync(_item), throwsStateError);
    expect(metadata.saves, isEmpty);
    expect(session.updates, isEmpty);
  });

  test('metadata write failure is still best effort for a found project', () async {
    final metadata = _Metadata(null)..failSave = true;
    final projects = _Projects([_project('found')]);
    final session = _Session();
    final result = await _resolver(projects, metadata, session).resolveAndSync(
      _item.copyWith(hasLyrics: false),
    );
    expect(result.projectId, 'found');
    expect(result.hasLyrics, isTrue);
    expect(result.repairedLink, isFalse);
    expect(session.updates.single.hasLyrics, isTrue);
  });

  test('invalid real project store does not clear persisted metadata', () async {
    final directory = await Directory.systemTemp.createTemp('lyric-store-failure-');
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}${Platform.pathSeparator}projects.json').writeAsString('{broken');
    final metadata = _Metadata(_linked());
    final session = _Session();
    final resolver = PlaybackLyricsResolver(
      projectRepository: FileProjectRepository(rootDirectory: directory),
      metadataRepository: metadata, playbackSession: session,
      pathCanonicalizer: const FileAudioPathCanonicalizer(),
    );
    await expectLater(resolver.resolveAndSync(_item), throwsA(isA<Exception>()));
    expect(metadata.saves, isEmpty);
    expect(session.updates, isEmpty);
    expect(await File('${directory.path}${Platform.pathSeparator}projects.json').readAsString(), '{broken');
  });

  for (final failReadAt in [1, 2]) {
    testWidgets('import stops and shows error when metadata read $failReadAt fails', (tester) async {
      final metadata = _Metadata(null)..failReadAt = failReadAt;
      final projects = _Projects([]);
      final session = _Session();
      final dependencies = LyricsImportDependencies(
        lyricsResolver: _resolver(projects, metadata, session), importer: _UnusedImporter(),
      );
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => importLyricsForLocalPlaybackItem(context, _item, dependencies),
        child: const Text('导入'),
      )))));
      await tester.tap(find.text('导入'));
      await tester.pumpAndSettle();
      expect(find.textContaining('无法读取歌曲或歌词工程，请检查存储后重试'), findsOneWidget);
      expect(projects.creates, 0);
      expect(metadata.saves, isEmpty);
      // First resolution can legitimately synchronize false before the second read.
      if (failReadAt == 1) expect(session.updates, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Now Playing exposes a retry and recovers after storage works', (tester) async {
    final projects = _Projects([_project('linked')])..failGet = true;
    final metadata = _Metadata(_linked());
    final session = _Session();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: NowPlayingLyricsProjectAction(
      item: _item, lyricsResolver: _resolver(projects, metadata, session), immersiveKtv: _UnusedImmersive(),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('歌词读取失败，重试'), findsOneWidget);
    expect(metadata.saves, isEmpty);
    expect(session.updates, isEmpty);
    projects.failGet = false;
    await tester.tap(find.text('歌词读取失败，重试'));
    await tester.pumpAndSettle();
    expect(find.text('全屏 KTV'), findsOneWidget);
    expect(find.text('歌词读取失败，重试'), findsNothing);
  });
}

class _Projects extends Fake implements ProjectRepository {
  _Projects(this.projects);
  final List<ProjectManifest> projects;
  bool failGet = false;
  bool failScan = false;
  int scans = 0;
  int creates = 0;
  @override
  Future<ProjectManifest?> getProjectById(String id) async {
    if (failGet) throw StateError('project read failed');
    for (final project in projects) { if (project.id == id) return project; }
    return null;
  }
  @override
  Future<List<ProjectManifest>> getAllProjects() async {
    scans++;
    if (failScan) throw StateError('scan failed');
    return projects;
  }
  @override
  Future<ProjectManifest> createProject({required String name, String? artist, String? album}) async {
    creates++;
    throw StateError('should not create a project');
  }
}

class _Metadata extends Fake implements LocalMediaMetadataRepository {
  _Metadata(this.existing);
  final LocalMediaMetadata? existing;
  final List<LocalMediaMetadata> saves = [];
  int reads = 0;
  int? failReadAt;
  bool failSave = false;
  @override
  Future<LocalMediaMetadata?> getForAudio(String sourcePath) async {
    reads++;
    if (reads == failReadAt) throw StateError('metadata read failed');
    return existing;
  }
  @override
  Future<LocalMediaMetadata> save(LocalMediaMetadata value) async {
    if (failSave) throw StateError('metadata write failed');
    saves.add(value);
    return value;
  }
}

class _Session extends Fake implements PlaybackSessionService {
  final List<PlaybackItem> updates = [];
  @override
  Future<void> updateItem(PlaybackItem item) async => updates.add(item);
}

class _FailingPaths extends Fake implements AudioPathCanonicalizer {
  @override
  String canonicalize(String path) => throw StateError('path failed');
}

class _UnusedImporter extends Fake implements LyricFileImportService {}
class _UnusedImmersive extends Fake implements ImmersiveKtvDependencies {}
