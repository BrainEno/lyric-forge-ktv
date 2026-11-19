import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_library_entry.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_library_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_path_canonicalizer.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/library_folder_settings.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/library_lyric_file_matcher.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/library_lyrics_auto_linker.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/library_lyrics_pairing.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_lyrics_project_linker.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/memory_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

void main() {
  late _Library library;
  late _Metadata metadata;
  late MemoryProjectRepository projects;
  late _Importer importer;
  late _Session session;
  late _Files files;
  late String? customFolder;

  LibraryLyricsAutoLinker linker() {
    final folderStore = _FolderStore(customFolder);
    return LibraryLyricsAutoLinker(
      library: library,
      metadata: metadata,
      projects: projects,
      importer: importer,
      playbackSession: session,
      pathCanonicalizer: const _SamePath(),
      folderSettings: LibraryFolderSettings(
        store: folderStore,
        library: library,
        systemMusicFolder: null,
      ),
      listFiles: files.list,
      clock: () => DateTime.utc(2026, 11, 28, 12),
    );
  }

  setUp(() {
    library = _Library();
    metadata = _Metadata();
    projects = MemoryProjectRepository();
    importer = _Importer();
    session = _Session();
    files = _Files();
    customFolder = '/曲库';
  });

  test('a file in the library folder gives the song a lyric project', () async {
    library.entries.add(
      _entry('/music/jay/01.mp3', title: '夜曲', artist: '周杰伦', ms: 226000),
    );
    files.byFolder['/曲库'] = ['/曲库/周杰伦 - 夜曲.lrc'];
    importer.results['/曲库/周杰伦 - 夜曲.lrc'] = _result('/曲库/周杰伦 - 夜曲.lrc');

    final result = await linker().linkAll();

    expect(result.folder.path, '/曲库');
    expect(result.linked.single.reason, LibraryLyricMatchReason.artistAndTitle);
    expect(result.failed, isEmpty);
    final project = (await projects.getAllProjects()).single;
    expect(project.name, '夜曲');
    expect(project.artist, '周杰伦');
    expect(project.audioAsset?.originalPath, '/music/jay/01.mp3');
    expect(project.audioAsset?.duration, const Duration(seconds: 226));
    expect(project.lyricDocument?.lines.single.text, '一群嗜血的蚂蚁');
    expect(project.status, ProjectStatus.ready);
    expect(project.metadata['lyricSource'], 'library-folder');
    final import = project.metadata['lyricImport'] as Map<String, dynamic>;
    expect(import['path'], '/曲库/周杰伦 - 夜曲.lrc');
    expect(import['automatic'], isTrue);
    expect(import['importedAt'], '2026-11-28T12:00:00.000Z');
    final link = metadata.stored['/music/jay/01.mp3']!.metadata;
    expect(link['linkedProjectId'], project.id);
    expect(link['hasLyrics'], isTrue);
  });

  test('a file beside the song is found without a library folder', () async {
    customFolder = null;
    library.entries.add(_entry('/music/jay/夜曲.flac'));
    files.byFolder['/music/jay'] = ['/music/jay/夜曲.lrc'];
    importer.results['/music/jay/夜曲.lrc'] = _result('/music/jay/夜曲.lrc');

    final result = await linker().linkAll();

    expect(result.folder, LibraryFolder.none);
    expect(result.linked.single.reason, LibraryLyricMatchReason.besideSong);
    expect(files.calls, [('/music/jay', false)]);
  });

  test('the library folder is searched deeply, song folders are not', () async {
    library.entries.addAll([
      _entry('/music/a/1.mp3'),
      _entry('/music/a/2.mp3'),
      _entry('/music/b/3.mp3'),
    ]);

    await linker().linkAll();

    expect(files.calls, [
      ('/曲库', true),
      ('/music/a', false),
      ('/music/b', false),
    ]);
    // Plain .txt files are not paired: too many are not lyrics.
    expect(files.extensions, {'lrc', 'srt', 'vtt', 'ass'});
  });

  test('songs that already have lyrics are never touched', () async {
    library.entries.addAll([
      _entry('/music/linked.mp3', title: '已链接'),
      _entry('/music/has-project.mp3', title: '有工程'),
    ]);
    metadata.stored['/music/linked.mp3'] = LocalMediaMetadata(
      sourcePath: '/music/linked.mp3',
      updatedAt: DateTime(2026),
      metadata: const {'linkedProjectId': 'p-1'},
    );
    final existing = await projects.createProject(name: '有工程');
    await projects.updateProject(
      existing.copyWith(
        audioAsset: const AudioAsset(
          originalPath: '/music/has-project.mp3',
          format: 'mp3',
        ),
        lyricDocument: _document('手工校对过的歌词'),
      ),
    );
    files.byFolder['/曲库'] = ['/曲库/已链接.lrc', '/曲库/有工程.lrc'];

    final result = await linker().linkAll();

    expect(result.linked, isEmpty);
    expect(files.calls, isEmpty);
    expect(importer.imported, isEmpty);
    final kept = await projects.getProjectById(existing.id);
    expect(kept?.lyricDocument?.lines.single.text, '手工校对过的歌词');
  });

  test('an empty project for the song is filled, not doubled', () async {
    library.entries.add(_entry('/music/晴天.mp3'));
    final empty = await projects.createProject(name: '晴天');
    await projects.updateProject(
      empty.copyWith(
        audioAsset: const AudioAsset(
          originalPath: '/music/晴天.mp3',
          format: 'mp3',
        ),
      ),
    );
    files.byFolder['/曲库'] = ['/曲库/晴天.lrc'];
    importer.results['/曲库/晴天.lrc'] = _result('/曲库/晴天.lrc');

    await linker().linkAll();

    final all = await projects.getAllProjects();
    expect(all, hasLength(1));
    expect(all.single.id, empty.id);
    expect(all.single.hasLyrics, isTrue);
  });

  test('a file that cannot be read is reported; others still link', () async {
    library.entries.addAll([
      _entry('/music/坏.mp3'),
      _entry('/music/空.mp3'),
      _entry('/music/好.mp3'),
    ]);
    files.byFolder['/曲库'] = ['/曲库/坏.lrc', '/曲库/空.lrc', '/曲库/好.lrc'];
    importer.results['/曲库/空.lrc'] = _result('/曲库/空.lrc', lines: const []);
    importer.results['/曲库/好.lrc'] = _result('/曲库/好.lrc');

    final result = await linker().linkAll();

    expect(result.failed, unorderedEquals(['/曲库/坏.lrc', '/曲库/空.lrc']));
    expect(result.linked.single.song.audioPath, '/music/好.mp3');
    expect(await projects.getAllProjects(), hasLength(1));
    expect(metadata.stored.keys, ['/music/好.mp3']);
  });

  test('missing songs are skipped', () async {
    library.entries.add(_entry('/music/gone.mp3', missing: true));
    files.byFolder['/曲库'] = ['/曲库/gone.lrc'];

    final result = await linker().linkAll();

    expect(result.changedAnything, isFalse);
    expect(files.calls, isEmpty);
  });

  test('a title the user edited is the one matched', () async {
    library.entries.add(_entry('/music/track07.mp3', title: 'Track 7'));
    metadata.stored['/music/track07.mp3'] = LocalMediaMetadata(
      sourcePath: '/music/track07.mp3',
      title: '稻香',
      updatedAt: DateTime(2026),
    );
    files.byFolder['/曲库'] = ['/曲库/稻香.lrc', '/曲库/Track 7.lrc'];
    importer.results['/曲库/稻香.lrc'] = _result('/曲库/稻香.lrc');

    final result = await linker().linkAll();

    expect(result.linked.single.lyricPath, '/曲库/稻香.lrc');
    expect((await projects.getAllProjects()).single.name, '稻香');
  });

  test('queued copies of the song learn it has lyrics', () async {
    library.entries.add(_entry('/music/夜曲.mp3'));
    session.currentState = PlaybackSessionState(
      queue: [
        PlaybackItem(
          id: 'q1',
          title: '夜曲',
          audioAsset: const AudioAsset(
            originalPath: '/music/夜曲.mp3',
            format: 'mp3',
          ),
        ),
      ],
      currentIndex: 0,
    );
    files.byFolder['/曲库'] = ['/曲库/夜曲.lrc'];
    importer.results['/曲库/夜曲.lrc'] = _result('/曲库/夜曲.lrc');

    await linker().linkAll();

    expect(session.currentState.queue.single.hasLyrics, isTrue);
  });

  test('calls during a pass share it instead of importing twice', () async {
    library.entries.add(_entry('/music/夜曲.mp3'));
    files.byFolder['/曲库'] = ['/曲库/夜曲.lrc'];
    importer.results['/曲库/夜曲.lrc'] = _result('/曲库/夜曲.lrc');
    importer.gate = Completer<void>();
    final shared = linker();

    final first = shared.linkAll();
    final second = shared.linkAll();
    importer.gate!.complete();
    final results = await Future.wait([first, second]);

    expect(identical(results[0], results[1]), isTrue);
    expect(importer.imported, ['/曲库/夜曲.lrc']);

    // Once finished, the next call runs a new pass: nothing left to link.
    final again = await shared.linkAll();
    expect(again.linked, isEmpty);
  });

  group('taking a pairing back (D-034)', () {
    const song = '/music/夜曲.mp3';
    const file = '/曲库/夜曲.lrc';

    setUp(() {
      library.entries.add(_entry(song));
      files.byFolder['/曲库'] = [file];
      importer.results[file] = _result(file);
    });

    Map<String, dynamic> stored() => metadata.stored[song]!.metadata;

    test('the song remembers how its lyrics were paired', () async {
      await linker().linkAll();

      final project = (await projects.getAllProjects()).single;
      final pairing = LibraryLyricsPairing.of(metadata.stored[song])!;
      expect(pairing.lyricPath, file);
      expect(pairing.projectId, project.id);
      expect(pairing.reason, LibraryLyricMatchReason.sameFileName);
      expect(pairing.createdProject, isTrue);
      expect(pairing.projectRevision, project.revision);
      expect(pairing.previousStatus, ProjectStatus.draft);
      expect(pairing.previousStage, ProcessingStage.none);
      expect(pairing.fingerprint, lyricLinesFingerprint(project.lyricDocument));
      expect(pairing.pairedAt, DateTime.utc(2026, 11, 28, 12));
    });

    test('an untouched project the pairing made is deleted', () async {
      session.currentState = PlaybackSessionState(
        queue: [
          PlaybackItem(
            id: 'q1',
            title: '夜曲',
            audioAsset: const AudioAsset(originalPath: song, format: 'mp3'),
          ),
        ],
        currentIndex: 0,
      );
      final shared = linker();
      await shared.linkAll();
      expect(session.currentState.queue.single.hasLyrics, isTrue);

      final result = await shared.unpair(song);

      expect(result.outcome, LibraryLyricsUnpairOutcome.unpaired);
      expect(result.removedProject, isTrue);
      expect(result.pairing?.lyricPath, file);
      expect(await projects.getAllProjects(), isEmpty);
      expect(stored().containsKey('linkedProjectId'), isFalse);
      expect(stored().containsKey('hasLyrics'), isFalse);
      expect(stored().containsKey(LibraryLyricsPairing.metadataKey), isFalse);
      expect(stored()[LibraryLyricsPairing.dismissedKey], [file]);
      expect(session.currentState.queue.single.hasLyrics, isFalse);

      // The next pass leaves the song alone instead of pairing it again.
      final again = await shared.linkAll();
      expect(again.linked, isEmpty);
      expect(importer.imported, [file]);
      expect(await projects.getAllProjects(), isEmpty);
    });

    test('a project the song already had is emptied, not deleted', () async {
      final empty = await projects.createProject(name: '夜曲');
      await projects.updateProject(
        empty.copyWith(
          status: ProjectStatus.processing,
          currentStage: ProcessingStage.vocalsSeparated,
          audioAsset: const AudioAsset(originalPath: song, format: 'mp3'),
        ),
      );
      final shared = linker();
      await shared.linkAll();
      expect((await projects.getProjectById(empty.id))?.hasLyrics, isTrue);

      final result = await shared.unpair(song);

      expect(result.outcome, LibraryLyricsUnpairOutcome.unpaired);
      expect(result.removedProject, isFalse);
      final kept = (await projects.getProjectById(empty.id))!;
      expect(kept.hasLyrics, isFalse);
      expect(kept.status, ProjectStatus.processing);
      expect(kept.currentStage, ProcessingStage.vocalsSeparated);
      expect(kept.audioAsset?.originalPath, song);
      expect(kept.metadata.containsKey('lyricImport'), isFalse);
      expect(kept.metadata.containsKey('lyricSource'), isFalse);
    });

    test('lyrics edited since the pairing are kept', () async {
      final shared = linker();
      await shared.linkAll();
      final paired = (await projects.getAllProjects()).single;
      await projects.updateProject(
        paired.copyWith(lyricDocument: _document('一群嗜血的蚂蚁 被腐肉所吸引')),
      );

      final result = await shared.unpair(song);

      expect(result.outcome, LibraryLyricsUnpairOutcome.editedSincePairing);
      final kept = (await projects.getProjectById(paired.id))!;
      expect(kept.lyricDocument?.lines.single.text, '一群嗜血的蚂蚁 被腐肉所吸引');
      expect(stored()['linkedProjectId'], paired.id);
      expect(stored().containsKey(LibraryLyricsPairing.dismissedKey), isFalse);
    });

    test('other saves to the project do not count as edits', () async {
      final shared = linker();
      await shared.linkAll();
      final paired = (await projects.getAllProjects()).single;
      await projects.updateProject(
        paired.copyWith(metadata: {...paired.metadata, 'viewed': true}),
      );

      final result = await shared.unpair(song);

      expect(result.outcome, LibraryLyricsUnpairOutcome.unpaired);
      // Changed since, so emptied rather than deleted.
      expect(result.removedProject, isFalse);
      final kept = (await projects.getProjectById(paired.id))!;
      expect(kept.hasLyrics, isFalse);
      expect(kept.metadata['viewed'], isTrue);
    });

    test('lyrics linked by hand are not unpaired', () async {
      metadata.stored[song] = LocalMediaMetadata(
        sourcePath: song,
        updatedAt: DateTime(2026),
        metadata: const {'linkedProjectId': 'p-9', 'hasLyrics': true},
      );

      final result = await linker().unpair(song);

      expect(result.outcome, LibraryLyricsUnpairOutcome.notAutoPaired);
      expect(stored()['linkedProjectId'], 'p-9');
    });

    test('undo pairs the same file with the song again', () async {
      final shared = linker();
      await shared.linkAll();
      final unpaired = await shared.unpair(song);

      final restored = await shared.pairAgain(song, unpaired.pairing!);

      expect(restored.linked.single.lyricPath, file);
      expect(
        restored.linked.single.reason,
        LibraryLyricMatchReason.sameFileName,
      );
      final project = (await projects.getAllProjects()).single;
      expect(project.hasLyrics, isTrue);
      expect(stored()['linkedProjectId'], project.id);
      expect(stored().containsKey(LibraryLyricsPairing.dismissedKey), isFalse);
      expect(LibraryLyricsPairing.of(metadata.stored[song])?.lyricPath, file);
    });

    test('undo leaves a song that got other lyrics meanwhile alone', () async {
      final shared = linker();
      await shared.linkAll();
      final unpaired = await shared.unpair(song);
      final manual = await projects.createProject(name: '夜曲');
      await projects.updateProject(
        manual.copyWith(
          audioAsset: const AudioAsset(originalPath: song, format: 'mp3'),
          lyricDocument: _document('手工输入的歌词'),
        ),
      );

      final restored = await shared.pairAgain(song, unpaired.pairing!);

      expect(restored.changedAnything, isFalse);
      expect(importer.imported, [file]);
    });

    test('counts the songs whose lyrics were paired on their own', () async {
      library.entries.add(_entry('/music/晴天.mp3'));
      files.byFolder['/曲库'] = [file, '/曲库/晴天.lrc'];
      importer.results['/曲库/晴天.lrc'] = _result('/曲库/晴天.lrc');
      final shared = linker();
      expect(await shared.autoPairedCount(), 0);

      await shared.linkAll();
      expect(await shared.autoPairedCount(), 2);

      await shared.unpair(song);
      expect(await shared.autoPairedCount(), 1);
    });

    test('the count skips hand links and removed songs', () async {
      final shared = linker();
      await shared.linkAll();
      metadata.stored['/music/手工.mp3'] = LocalMediaMetadata(
        sourcePath: '/music/手工.mp3',
        updatedAt: DateTime(2026),
        metadata: const {'linkedProjectId': 'p-9', 'hasLyrics': true},
      );
      library.entries.add(_entry('/music/手工.mp3'));
      expect(await shared.autoPairedCount(), 1);

      library.entries.removeWhere((entry) => entry.sourcePath == song);
      expect(await shared.autoPairedCount(), 0);
    });

    test('linking the song by hand drops the old record', () async {
      await linker().linkAll();
      expect(LibraryLyricsPairing.of(metadata.stored[song]), isNotNull);

      await linkPlaybackLyricsProject(
        audioPath: song,
        projectId: 'manual',
        metadataRepository: metadata,
        playbackSession: session,
        pathCanonicalizer: const _SamePath(),
      );

      expect(stored()['linkedProjectId'], 'manual');
      expect(stored().containsKey(LibraryLyricsPairing.metadataKey), isFalse);
    });
  });
}

LocalMediaLibraryEntry _entry(
  String path, {
  String? title,
  String? artist,
  int? ms,
  bool missing = false,
}) {
  return LocalMediaLibraryEntry(
    sourcePath: path,
    format: path.substring(path.lastIndexOf('.') + 1),
    addedAt: DateTime(2026),
    lastSeenAt: DateTime(2026),
    isMissing: missing,
    embeddedTitle: title,
    embeddedArtist: artist,
    durationMs: ms,
  );
}

LyricDocument _document(String text) {
  return LyricDocument(
    language: 'zh',
    lines: [
      LyricLine(
        text: text,
        startTime: Duration.zero,
        endTime: const Duration(seconds: 3),
      ),
    ],
    metadata: const {'timed': true},
  );
}

LyricImportResult _result(String path, {List<LyricLine>? lines}) {
  final document = _document('一群嗜血的蚂蚁');
  return LyricImportResult(
    document: lines == null ? document : document.copyWith(lines: lines),
    format: LyricImportFormat.lrc,
    sourcePath: path,
    detectedEncoding: 'utf-8',
  );
}

class _SamePath implements AudioPathCanonicalizer {
  const _SamePath();

  @override
  String canonicalize(String path) => path;
}

class _FolderStore implements LibraryFolderStore {
  _FolderStore(this.folder);

  String? folder;

  @override
  Future<String?> loadFolder() async => folder;

  @override
  Future<void> saveFolder(String? path) async => folder = path;
}

class _Files {
  final Map<String, List<String>> byFolder = {};
  final List<(String, bool)> calls = [];
  Set<String>? extensions;

  Future<List<String>> list(
    String directory, {
    required bool recursive,
    required Set<String> extensions,
  }) async {
    calls.add((directory, recursive));
    this.extensions = extensions;
    return byFolder[directory] ?? const [];
  }
}

class _Importer implements LyricFileImportService {
  final Map<String, LyricImportResult> results = {};
  final List<String> imported = [];
  Completer<void>? gate;

  @override
  Set<String> get supportedExtensions => const {
    'lrc',
    'srt',
    'vtt',
    'ass',
    'txt',
  };

  @override
  Future<LyricImportResult> importFile(
    String path, {
    String? encodingHint,
  }) async {
    final pending = gate;
    if (pending != null) await pending.future;
    imported.add(path);
    final result = results[path];
    if (result == null) throw const LyricImportException('无法解码歌词文件');
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Library implements LocalMediaLibraryRepository {
  final List<LocalMediaLibraryEntry> entries = [];

  @override
  Future<List<LocalMediaLibraryEntry>> getAll() async => List.of(entries);

  @override
  Future<List<String>> getRoots() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Metadata implements LocalMediaMetadataRepository {
  final Map<String, LocalMediaMetadata> stored = {};

  @override
  Future<LocalMediaMetadata?> getForAudio(String sourcePath) async =>
      stored[sourcePath];

  @override
  Future<List<LocalMediaMetadata>> getAll() async => stored.values.toList();

  @override
  Future<LocalMediaMetadata> save(LocalMediaMetadata metadata) async {
    stored[metadata.sourcePath] = metadata;
    return metadata;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements PlaybackSessionService {
  @override
  PlaybackSessionState currentState = const PlaybackSessionState();

  @override
  Future<void> updateItem(PlaybackItem item) async {
    final queue = [
      for (final queued in currentState.queue)
        queued.id == item.id ? item : queued,
    ];
    currentState = currentState.copyWith(queue: queue);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
