import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_library_entry.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_playlist.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_collection_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_library_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';
import 'package:lyric_forge_ktv/features/search/data/local_global_search_source.dart';
import 'package:lyric_forge_ktv/features/search/domain/global_search_item.dart';

LocalMediaLibraryEntry _entry(
  String path, {
  String? title,
  String? artist,
  String? album,
  bool missing = false,
}) => LocalMediaLibraryEntry(
  sourcePath: path,
  format: 'mp3',
  addedAt: DateTime(2026),
  lastSeenAt: DateTime(2026),
  isMissing: missing,
  embeddedTitle: title,
  embeddedArtist: artist,
  embeddedAlbum: album,
);

ProjectManifest _project(
  String id,
  String name, {
  required DateTime updatedAt,
  List<String> lines = const [],
}) => ProjectManifest(
  id: id,
  name: name,
  artist: 'Beyond',
  createdAt: DateTime(2026),
  updatedAt: updatedAt,
  audioAsset: AudioAsset(originalPath: '/music/$id.flac', format: 'flac'),
  lyricDocument: lines.isEmpty
      ? null
      : LyricDocument(
          language: 'zh',
          lines: [
            for (final text in lines)
              LyricLine(
                text: text,
                startTime: Duration.zero,
                endTime: const Duration(seconds: 1),
              ),
          ],
        ),
);

void main() {
  late _Projects projects;
  late _Library library;
  late _Metadata metadata;
  late _Collections collections;

  LocalGlobalSearchSource source({bool phone = false}) =>
      LocalGlobalSearchSource(
        projectRepository: projects,
        libraryRepository: library,
        metadataRepository: metadata,
        collectionRepository: collections,
        phone: phone,
      );

  setUp(() {
    projects = _Projects([
      _project('old', '光辉岁月', updatedAt: DateTime(2026, 1)),
      _project(
        'new',
        '海阔天空',
        updatedAt: DateTime(2026, 6),
        lines: ['今天我 寒夜里看雪飘过', '  ', '原谅我这一生不羁放纵爱自由'],
      ),
    ]);
    library = _Library([
      _entry('/music/a.mp3', title: 'Tagged', artist: 'Artist', album: 'LP'),
      _entry('/music/Untagged Song.flac'),
      _entry('/music/gone.mp3', title: 'Gone', missing: true),
    ]);
    metadata = _Metadata([
      LocalMediaMetadata(
        sourcePath: '/music/a.mp3',
        title: 'My Title',
        artist: 'My Artist',
        updatedAt: DateTime(2026),
      ),
    ]);
    collections = _Collections([
      LocalPlaylist(
        id: 'p1',
        name: '开车听',
        description: '周末',
        sourcePaths: const ['/music/gone.mp3', '/music/a.mp3'],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ]);
  });

  test('songs use the user’s own title and skip missing files', () async {
    final items = await source().load();
    final songs = items.where((item) => item.kind == GlobalSearchKind.song);
    expect(songs.map((item) => item.title), ['My Title', 'Untagged Song']);
    final tagged = songs.first;
    expect(tagged.subtitle, 'My Artist · LP');
    expect(tagged.keywords, ['a.mp3']);
    final song = (tagged.target as PlaySongTarget).item;
    expect(song.id, 'local:/music/a.mp3');
    expect(song.artist, 'My Artist');
    expect(song.audioAsset.originalPath, '/music/a.mp3');
  });

  test('projects come newest first with their lyric lines', () async {
    final items = await source().load();
    final found = items.where((item) => item.kind == GlobalSearchKind.project);
    expect(found.map((item) => item.title), ['海阔天空', '光辉岁月']);
    final newest = found.first;
    expect(newest.subtitle, 'Beyond · 2 行歌词');
    expect(newest.lyricLines, ['今天我 寒夜里看雪飘过', '原谅我这一生不羁放纵爱自由']);
    expect(newest.keywords, ['new.flac']);
    expect((newest.target as OpenRouteTarget).route, '/project/new');
    expect(found.last.subtitle, 'Beyond · 还没有歌词');
  });

  test('a playlist opens in the library and plays what it can', () async {
    final items = await source().load();
    final playlist = items.singleWhere(
      (item) => item.kind == GlobalSearchKind.playlist,
    );
    expect(playlist.subtitle, '2 首 · 周末');
    final target = playlist.target as OpenPlaylistTarget;
    expect(target.route, '/playlists?playlist=p1');
    expect(target.songs.map((song) => song.title), ['My Title']);
  });

  test('pages come first, the phone’s own on a phone', () async {
    final desktop = await source().load();
    expect(desktop.first.kind, GlobalSearchKind.action);
    expect(desktop.map((item) => item.id), contains('import'));
    final phone = await source(phone: true).load();
    expect(phone.map((item) => item.id), isNot(contains('import')));
  });

  test('a store that fails leaves the others searchable', () async {
    library.fail = true;
    final items = await source().load();
    expect(items.where((item) => item.kind == GlobalSearchKind.song), isEmpty);
    expect(
      items.where((item) => item.kind == GlobalSearchKind.project),
      hasLength(2),
    );
    final playlist = items.singleWhere(
      (item) => item.kind == GlobalSearchKind.playlist,
    );
    expect((playlist.target as OpenPlaylistTarget).songs, isEmpty);
  });

  test('Windows paths match whatever their case and slashes', () {
    expect(
      LocalGlobalSearchSource.pathKey(r'C:\Music\A.mp3'),
      LocalGlobalSearchSource.pathKey('c:/music/a.mp3'),
    );
    expect(
      LocalGlobalSearchSource.pathKey('/Music/A.mp3'),
      isNot(LocalGlobalSearchSource.pathKey('/music/a.mp3')),
    );
  });
}

class _Projects extends Fake implements ProjectRepository {
  _Projects(this.projects);

  final List<ProjectManifest> projects;

  @override
  Future<List<ProjectManifest>> getAllProjects() async => projects;
}

class _Library extends Fake implements LocalMediaLibraryRepository {
  _Library(this.entries);

  final List<LocalMediaLibraryEntry> entries;
  bool fail = false;

  @override
  Future<List<LocalMediaLibraryEntry>> getAll() async {
    if (fail) throw StateError('library is locked');
    return entries;
  }
}

class _Metadata extends Fake implements LocalMediaMetadataRepository {
  _Metadata(this.items);

  final List<LocalMediaMetadata> items;

  @override
  Future<List<LocalMediaMetadata>> getAll() async => items;
}

class _Collections extends Fake implements LocalMediaCollectionRepository {
  _Collections(this.playlists);

  final List<LocalPlaylist> playlists;

  @override
  Future<List<LocalPlaylist>> getPlaylists() async => playlists;
}
