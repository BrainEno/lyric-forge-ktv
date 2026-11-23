import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/services/project_duplicate_finder.dart';

ProjectManifest _project(
  String id, {
  String name = 'Song',
  String? artist,
  String? path,
  Duration? length,
  ProcessingStage stage = ProcessingStage.audioImported,
  int lines = 0,
  int updatedDay = 1,
}) => ProjectManifest(
  id: id,
  name: name,
  artist: artist,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026, 12, updatedDay),
  currentStage: stage,
  audioAsset: path == null
      ? null
      : AudioAsset(originalPath: path, format: 'mp3', duration: length),
  lyricDocument: lines == 0
      ? null
      : LyricDocument(
          language: 'en',
          lines: [
            for (var index = 0; index < lines; index++)
              LyricLine(
                text: 'line $index',
                startTime: Duration(seconds: index),
                endTime: Duration(seconds: index + 1),
              ),
          ],
        ),
);

void main() {
  const finder = ProjectDuplicateFinder();

  test('projects of one audio file are one group, the best first', () {
    final groups = finder.find([
      _project('draft', path: '/m/a.mp3', updatedDay: 9),
      _project('other', path: '/m/b.mp3'),
      _project(
        'edited',
        path: '/m/a.mp3',
        stage: ProcessingStage.lyricsEdited,
        lines: 20,
      ),
      _project(
        'recognised',
        path: '/m/a.mp3',
        stage: ProcessingStage.transcriptionComplete,
        lines: 30,
        updatedDay: 20,
      ),
    ]);

    expect(groups, hasLength(1));
    final group = groups.single;
    expect(group.reason, ProjectDuplicateReason.sameAudio);
    expect(group.projects.map((p) => p.id), ['edited', 'recognised', 'draft']);
    expect(group.keep.id, 'edited');
    expect(group.extras.map((p) => p.id), ['recognised', 'draft']);
    expect(ProjectDuplicateFinder.keepReason(group), '歌词校对过');
  });

  test('paths are compared after canonicalising', () {
    final caseless = ProjectDuplicateFinder(
      canonicalize: (path) => path.toLowerCase(),
    );
    final groups = caseless.find([
      _project('a', path: r'C:\Music\Song.MP3'),
      _project('b', path: r'c:\music\song.mp3'),
    ]);
    expect(groups.single.projects, hasLength(2));
  });

  test('same title, artist and length in two files is the same song', () {
    final groups = finder.find([
      _project(
        'a',
        name: 'Light My Fire',
        artist: 'The Doors',
        path: '/x/light.mp3',
        length: const Duration(seconds: 428),
      ),
      _project(
        'b',
        name: 'light my fire ',
        artist: 'the doors',
        path: '/y/Light My Fire.flac',
        length: const Duration(milliseconds: 429500),
        lines: 3,
      ),
      // A different version: too far apart.
      _project(
        'live',
        name: 'Light My Fire',
        artist: 'The Doors',
        path: '/z/live.mp3',
        length: const Duration(seconds: 600),
      ),
      // Unknown length: not assumed equal.
      _project(
        'unknown',
        name: 'Light My Fire',
        artist: 'The Doors',
        path: '/w/x.mp3',
      ),
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.reason, ProjectDuplicateReason.sameSong);
    expect(groups.single.projects.map((p) => p.id), ['b', 'a']);
    expect(ProjectDuplicateFinder.keepReason(groups.single), '只有它有歌词');
  });

  test('no duplicates, no groups; larger groups come first', () {
    expect(
      finder.find([_project('a', path: '/a'), _project('b', path: '/b')]),
      isEmpty,
    );
    final groups = finder.find([
      _project('a1', name: 'A', path: '/a'),
      _project('a2', name: 'A', path: '/a'),
      _project('b1', name: 'B', path: '/b'),
      _project('b2', name: 'B', path: '/b'),
      _project('b3', name: 'B', path: '/b'),
    ]);
    expect(groups.map((g) => g.projects.length), [3, 2]);
  });

  test('without lyrics or progress the most recent one is kept', () {
    final group = finder.find([
      _project('old', path: '/a', updatedDay: 1),
      _project('new', path: '/a', updatedDay: 5),
    ]).single;
    expect(group.keep.id, 'new');
    expect(ProjectDuplicateFinder.keepReason(group), '最近修改');
  });
}
