import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/song_info_update.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';

const _path = '/music/导入的视频 2026-11-18 14.46.m4a';
const _asset = AudioAsset(originalPath: _path, format: 'm4a');

PlaybackItem _local({bool hasLyrics = true}) => PlaybackItem(
  id: 'local:$_path',
  title: '导入的视频 2026-11-18 14.46',
  audioAsset: _asset,
  hasLyrics: hasLyrics,
);

PlaybackItem _projectItem() => const PlaybackItem(
  id: 'project:p1',
  title: '导入的视频 2026-11-18 14.46',
  projectId: 'p1',
  hasLyrics: true,
  audioAsset: _asset,
);

PlaybackItem _other() => const PlaybackItem(
  id: 'local:/music/other.mp3',
  title: '别的歌',
  audioAsset: AudioAsset(originalPath: '/music/other.mp3', format: 'mp3'),
);

LocalMediaMetadata _saved({String? artist = '周杰伦', String? link = 'p1'}) =>
    LocalMediaMetadata(
      sourcePath: _path,
      title: '晴天',
      artist: artist,
      updatedAt: DateTime(2026, 11, 18),
      metadata: {'linkedProjectId': ?link},
    );

ProjectManifest _project({String? artist}) => ProjectManifest(
  id: 'p1',
  name: '导入的视频 2026-11-18 14.46',
  artist: artist,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
  audioAsset: _asset,
  revision: 3,
);

class _Session extends Fake implements PlaybackSessionService {
  _Session(List<PlaybackItem> queue)
    : _state = PlaybackSessionState(queue: queue, currentIndex: 0);

  PlaybackSessionState _state;
  final updates = <PlaybackItem>[];

  @override
  PlaybackSessionState get currentState => _state;

  @override
  Future<void> updateItem(PlaybackItem item) async {
    updates.add(item);
    _state = PlaybackSessionState(
      queue: [
        for (final entry in _state.queue) entry.id == item.id ? item : entry,
      ],
      currentIndex: _state.currentIndex,
    );
  }
}

class _Projects extends Fake implements ProjectRepository {
  _Projects(this.project, {this.failing = false});

  ProjectManifest? project;
  final bool failing;
  final saved = <ProjectManifest>[];

  @override
  Future<ProjectManifest?> getProjectById(String id) async {
    if (failing) throw StateError('disk');
    return project?.id == id ? project : null;
  }

  @override
  Future<ProjectManifest> updateProject(ProjectManifest next) async {
    saved.add(next);
    project = next;
    return next;
  }
}

void main() {
  test('renames the linked lyric project with the song', () async {
    final projects = _Projects(_project());
    final result = await applySongInfoUpdate(
      saved: _saved(),
      fallbackTitle: '未命名歌曲',
      session: _Session([]),
      projectRepository: projects,
      now: DateTime(2026, 11, 18, 9),
    );

    expect(result.projectUpdated, isTrue);
    expect(projects.project!.name, '晴天');
    expect(projects.project!.artist, '周杰伦');
    expect(projects.project!.updatedAt, DateTime(2026, 11, 18, 9));
    // Everything else stays.
    expect(projects.project!.revision, 3);
    expect(projects.project!.audioAsset!.originalPath, _path);
  });

  test('relabels both the song and its lyric project in the queue', () async {
    final session = _Session([_projectItem(), _local(), _other()]);
    final result = await applySongInfoUpdate(
      saved: _saved(),
      fallbackTitle: '未命名歌曲',
      session: session,
      projectRepository: _Projects(_project()),
    );

    expect(result.queueItemsUpdated, 2);
    final queue = session.currentState.queue;
    expect(queue[0].title, '晴天');
    expect(queue[0].artist, '周杰伦');
    expect(queue[0].projectId, 'p1');
    expect(queue[1].title, '晴天');
    expect(queue[2].title, '别的歌');
  });

  test('keeps the lyric flag of the queue, not a stale copy', () async {
    final session = _Session([_local(hasLyrics: true)]);
    await applySongInfoUpdate(
      saved: _saved(link: null),
      fallbackTitle: '未命名歌曲',
      session: session,
    );
    expect(session.currentState.queue.single.hasLyrics, isTrue);
  });

  test('a link on the file marks the song as having lyrics', () async {
    final session = _Session([_local(hasLyrics: false)]);
    await applySongInfoUpdate(
      saved: _saved(),
      fallbackTitle: '未命名歌曲',
      session: session,
    );
    expect(session.currentState.queue.single.hasLyrics, isTrue);
  });

  test('a cleared artist is cleared on the project and in the queue', () async {
    final projects = _Projects(_project(artist: '旧艺人'));
    final session = _Session([_local().copyWith(artist: '旧艺人')]);
    await applySongInfoUpdate(
      saved: _saved(artist: null),
      fallbackTitle: '未命名歌曲',
      session: session,
      projectRepository: projects,
    );
    expect(projects.project!.artist, isNull);
    expect(projects.project!.name, '晴天');
    expect(session.currentState.queue.single.artist, isNull);
  });

  test('a project already named so is not written', () async {
    final projects = _Projects(_project(artist: '周杰伦').copyWith(name: '晴天'));
    final result = await applySongInfoUpdate(
      saved: _saved(),
      fallbackTitle: '未命名歌曲',
      session: _Session([]),
      projectRepository: projects,
    );
    expect(result.projectUpdated, isFalse);
    expect(projects.saved, isEmpty);
  });

  test('a failing project store still relabels the queue', () async {
    final session = _Session([_local()]);
    final result = await applySongInfoUpdate(
      saved: _saved(),
      fallbackTitle: '未命名歌曲',
      session: session,
      projectRepository: _Projects(_project(), failing: true),
    );
    expect(result.projectUpdated, isFalse);
    expect(result.projectError, isA<StateError>());
    expect(session.currentState.queue.single.title, '晴天');
  });

  test('without a title the fallback is used', () async {
    final session = _Session([_local()]);
    await applySongInfoUpdate(
      saved: LocalMediaMetadata(
        sourcePath: _path,
        updatedAt: DateTime(2026, 11, 18),
      ),
      fallbackTitle: '未命名歌曲',
      session: session,
    );
    expect(session.currentState.queue.single.title, '未命名歌曲');
  });

  test('linkedProjectIdOf ignores blanks and non-strings', () {
    LocalMediaMetadata withLink(Object? link) => LocalMediaMetadata(
      sourcePath: _path,
      updatedAt: DateTime(2026),
      metadata: {'linkedProjectId': link},
    );
    expect(linkedProjectIdOf(withLink(' p1 ')), 'p1');
    expect(linkedProjectIdOf(withLink('  ')), isNull);
    expect(linkedProjectIdOf(withLink(7)), isNull);
    expect(linkedProjectIdOf(null), isNull);
  });
}
