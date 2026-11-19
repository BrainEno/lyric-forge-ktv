import '../../../lyrics/domain/services/lyric_file_import_service.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../models/local_media_library_entry.dart';
import '../models/local_media_metadata.dart';
import '../repositories/local_media_library_repository.dart';
import '../repositories/local_media_metadata_repository.dart';
import 'audio_path_canonicalizer.dart';
import 'imported_lyrics_project.dart';
import 'library_folder_settings.dart';
import 'library_lyric_file_matcher.dart';
import 'library_lyrics_pairing.dart';
import 'playback_lyrics_project_linker.dart';
import 'playback_session_service.dart';

/// Lists files under [directory] whose extension (lower case, no dot) is in
/// [extensions]. Implementations return an empty list for a folder that
/// does not exist or cannot be read.
typedef LyricFileLister =
    Future<List<String>> Function(
      String directory, {
      required bool recursive,
      required Set<String> extensions,
    });

/// What one pass of [LibraryLyricsAutoLinker.linkAll] did.
class LibraryLyricsLinkResult {
  const LibraryLyricsLinkResult({
    this.folder = LibraryFolder.none,
    this.linked = const [],
    this.failed = const [],
  });

  /// The library folder that was searched.
  final LibraryFolder folder;

  /// Songs that now have lyrics, with the file each one got.
  final List<LibraryLyricMatch> linked;

  /// Files that matched a song but could not be read or saved.
  final List<String> failed;

  bool get changedAnything => linked.isNotEmpty;
}

/// How [LibraryLyricsAutoLinker.unpair] ended.
enum LibraryLyricsUnpairOutcome {
  /// The song no longer has the paired lyrics, and the file will not be
  /// paired with it again.
  unpaired,

  /// The song's lyrics were not paired automatically; nothing changed.
  notAutoPaired,

  /// The paired lyrics were edited since; nothing changed, so the edits
  /// are not lost.
  editedSincePairing,
}

/// What [LibraryLyricsAutoLinker.unpair] did.
class LibraryLyricsUnpairResult {
  const LibraryLyricsUnpairResult(
    this.outcome, {
    this.pairing,
    this.removedProject = false,
  });

  final LibraryLyricsUnpairOutcome outcome;

  /// The pairing that was looked at, when there was one.
  final LibraryLyricsPairing? pairing;

  /// Whether the project the pairing had created was deleted, rather than
  /// emptied of the paired lyrics.
  final bool removedProject;
}

/// Gives library songs the lyric files saved for them (decision D-033).
///
/// A user who exported lyrics as a file and saved it in the library folder,
/// or next to the song, expects the app to know the song now has lyrics.
/// Before this, the file was ignored until they found 导入歌词 on that song
/// and picked the same file again.
///
/// Each pass looks at songs without lyrics only: a song linked to a lyric
/// project, or with a project for its audio that has lyrics, is never
/// touched, so an edited project is not replaced by an older file. Files
/// are searched in the library folder (with subfolders) and in each such
/// song's own folder, and paired by [LibraryLyricFileMatcher]. Each pairing
/// creates (or fills) the song's project exactly like 导入歌词 does and
/// links it, so the library, the player and the editor all see it.
class LibraryLyricsAutoLinker {
  LibraryLyricsAutoLinker({
    required this.library,
    required this.metadata,
    required this.projects,
    required this.importer,
    required this.playbackSession,
    required this.pathCanonicalizer,
    required this.folderSettings,
    required this.listFiles,
    this.matcher = const LibraryLyricFileMatcher(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LocalMediaLibraryRepository library;
  final LocalMediaMetadataRepository metadata;
  final ProjectRepository projects;
  final LyricFileImportService importer;
  final PlaybackSessionService playbackSession;
  final AudioPathCanonicalizer pathCanonicalizer;
  final LibraryFolderSettings folderSettings;
  final LyricFileLister listFiles;
  final LibraryLyricFileMatcher matcher;
  final DateTime Function() _clock;

  Future<LibraryLyricsLinkResult>? _running;

  /// Pairs and imports every lyric file that belongs to a song without
  /// lyrics. Calls made while a pass runs share that pass.
  Future<LibraryLyricsLinkResult> linkAll() {
    final running = _running;
    if (running != null) return running;
    final pass = _linkAll();
    _running = pass;
    return pass.whenComplete(() => _running = null);
  }

  Future<LibraryLyricsLinkResult> _linkAll() async {
    final folder = await folderSettings.current();
    final candidates = await _songsWithoutLyrics();
    if (candidates.isEmpty) return LibraryLyricsLinkResult(folder: folder);

    final extensions = {
      for (final extension in importer.supportedExtensions)
        if (matcher.preferredExtensions.contains(extension.toLowerCase()))
          extension.toLowerCase(),
    };
    final files = <String>{};
    final folderPath = folder.path;
    if (folderPath != null) {
      files.addAll(
        await listFiles(folderPath, recursive: true, extensions: extensions),
      );
    }
    final songFolders = <String>{};
    for (final candidate in candidates) {
      final songFolder = _parentOf(candidate.song.audioPath);
      if (songFolder == null || !songFolders.add(songFolder)) continue;
      files.addAll(
        await listFiles(songFolder, recursive: false, extensions: extensions),
      );
    }
    if (files.isEmpty) return LibraryLyricsLinkResult(folder: folder);

    final matches = matcher.match(
      songs: [for (final candidate in candidates) candidate.song],
      lyricFiles: files,
    );
    final bySong = {
      for (final candidate in candidates) candidate.song: candidate,
    };
    final linked = <LibraryLyricMatch>[];
    final failed = <String>[];
    for (final match in matches) {
      final candidate = bySong[match.song]!;
      // The user took this file back from this song (D-034).
      if (candidate.dismissed.contains(_key(match.lyricPath))) continue;
      try {
        await _attach(candidate, match);
        linked.add(match);
      } on Exception {
        failed.add(match.lyricPath);
      }
    }
    return LibraryLyricsLinkResult(
      folder: folder,
      linked: linked,
      failed: failed,
    );
  }

  Future<List<_Candidate>> _songsWithoutLyrics() async {
    final entries = await library.getAll();
    final overrides = <String, LocalMediaMetadata>{
      for (final item in await metadata.getAll())
        pathCanonicalizer.canonicalize(item.sourcePath): item,
    };
    final projectByAudio = <String, ProjectManifest>{};
    for (final project in await projects.getAllProjects()) {
      final audioPath = project.audioAsset?.originalPath;
      if (audioPath == null || audioPath.trim().isEmpty) continue;
      final key = pathCanonicalizer.canonicalize(audioPath);
      final previous = projectByAudio[key];
      // Prefer the project that already has lyrics.
      if (previous == null || (!previous.hasLyrics && project.hasLyrics)) {
        projectByAudio[key] = project;
      }
    }

    final candidates = <_Candidate>[];
    for (final entry in entries) {
      if (entry.isMissing) continue;
      final key = pathCanonicalizer.canonicalize(entry.sourcePath);
      final override = overrides[key];
      final linkedId = override?.metadata['linkedProjectId'];
      if (linkedId is String && linkedId.trim().isNotEmpty) continue;
      final existing = projectByAudio[key];
      if (existing != null && existing.hasLyrics) continue;
      candidates.add(
        _Candidate(entry, override, existing, dismissed: _dismissed(override)),
      );
    }
    return candidates;
  }

  Set<String> _dismissed(LocalMediaMetadata? metadata) => {
    for (final path in LibraryLyricsPairing.dismissedFiles(metadata))
      _key(path),
  };

  String _key(String path) => pathCanonicalizer.canonicalize(path);

  Future<void> _attach(_Candidate candidate, LibraryLyricMatch match) async {
    final result = await importer.importFile(match.lyricPath);
    if (result.document.lines.isEmpty) {
      throw const LyricImportException('歌词文件里没有歌词');
    }
    final song = candidate.song;
    final existing = candidate.project;
    final project =
        existing ??
        await projects.createProject(
          name: song.title,
          artist: song.artist ?? result.artist,
          album: candidate.album ?? result.album,
        );
    final updated = projectWithImportedLyrics(
      project,
      title: song.title,
      artist: song.artist,
      audioAsset: AudioAsset(
        originalPath: candidate.entry.sourcePath,
        format: candidate.entry.format,
        duration: candidate.duration,
      ),
      artworkPath: candidate.artworkPath,
      result: result,
      now: _clock(),
      source: 'library-folder',
      automatic: true,
    );
    final saved = await projects.updateProject(updated);
    await linkPlaybackLyricsProject(
      audioPath: candidate.entry.sourcePath,
      projectId: saved.id,
      metadataRepository: metadata,
      playbackSession: playbackSession,
      pathCanonicalizer: pathCanonicalizer,
      pairing: LibraryLyricsPairing(
        lyricPath: match.lyricPath,
        projectId: saved.id,
        reason: match.reason,
        createdProject: existing == null,
        projectRevision: saved.revision,
        previousStatus: project.status,
        previousStage: project.currentStage,
        fingerprint: lyricLinesFingerprint(saved.lyricDocument),
        pairedAt: _clock(),
      ),
    );
  }

  /// Takes back the lyrics paired with the song at [audioPath] (D-034).
  ///
  /// A project the pairing created and nobody changed since is deleted; a
  /// project it filled, or one changed in other ways, loses only the paired
  /// lyrics and goes back to its earlier status. Lyrics edited since the
  /// pairing are kept and nothing changes. The song is unlinked, queued
  /// copies learn it has no lyrics, and the file is remembered so the next
  /// pass does not pair it with this song again. The file is not touched.
  Future<LibraryLyricsUnpairResult> unpair(String audioPath) async {
    final stored = await readCompleteLocalMediaMetadataForAudio(
      metadata,
      audioPath,
    );
    final pairing = LibraryLyricsPairing.of(stored);
    if (stored == null || pairing == null) {
      return const LibraryLyricsUnpairResult(
        LibraryLyricsUnpairOutcome.notAutoPaired,
      );
    }

    final project = await projects.getProjectById(pairing.projectId);
    var removedProject = false;
    if (project != null && project.hasLyrics) {
      final current = lyricLinesFingerprint(project.lyricDocument);
      if (current != pairing.fingerprint) {
        return LibraryLyricsUnpairResult(
          LibraryLyricsUnpairOutcome.editedSincePairing,
          pairing: pairing,
        );
      }
      if (pairing.createdProject &&
          project.revision == pairing.projectRevision) {
        await projects.deleteProject(project.id);
        removedProject = true;
      } else {
        await projects.updateProjectIfUnchanged(
          projectWithoutPairedLyrics(project, pairing),
          expectedRevision: project.revision,
        );
      }
    }

    final dismissed = {
      ...LibraryLyricsPairing.dismissedFiles(stored),
      pairing.lyricPath,
    };
    final kept = {...stored.metadata}
      ..remove('linkedProjectId')
      ..remove('hasLyrics')
      ..remove(LibraryLyricsPairing.metadataKey);
    await metadata.save(
      stored.copyWith(
        updatedAt: _clock(),
        metadata: {
          ...kept,
          LibraryLyricsPairing.dismissedKey: dismissed.toList()..sort(),
        },
      ),
    );
    await _markQueuedCopiesWithoutLyrics(audioPath);
    return LibraryLyricsUnpairResult(
      LibraryLyricsUnpairOutcome.unpaired,
      pairing: pairing,
      removedProject: removedProject,
    );
  }

  /// Pairs the file of [pairing] with the song at [audioPath] again: the
  /// undo of [unpair]. The file is no longer remembered as unpaired; a song
  /// that got lyrics in the meantime keeps them.
  Future<LibraryLyricsLinkResult> pairAgain(
    String audioPath,
    LibraryLyricsPairing pairing,
  ) async {
    final stored = await readCompleteLocalMediaMetadataForAudio(
      metadata,
      audioPath,
    );
    if (stored != null) {
      final file = _key(pairing.lyricPath);
      final dismissed = [
        for (final path in LibraryLyricsPairing.dismissedFiles(stored))
          if (_key(path) != file) path,
      ]..sort();
      final kept = {...stored.metadata}
        ..remove(LibraryLyricsPairing.dismissedKey);
      await metadata.save(
        stored.copyWith(
          updatedAt: _clock(),
          metadata: {
            ...kept,
            if (dismissed.isNotEmpty)
              LibraryLyricsPairing.dismissedKey: dismissed,
          },
        ),
      );
    }

    final folder = await folderSettings.current();
    final song = _key(audioPath);
    final candidates = await _songsWithoutLyrics();
    for (final candidate in candidates) {
      if (_key(candidate.entry.sourcePath) != song) continue;
      final match = LibraryLyricMatch(
        song: candidate.song,
        lyricPath: pairing.lyricPath,
        reason: pairing.reason,
      );
      try {
        await _attach(candidate, match);
      } on Exception {
        return LibraryLyricsLinkResult(
          folder: folder,
          failed: [pairing.lyricPath],
        );
      }
      return LibraryLyricsLinkResult(folder: folder, linked: [match]);
    }
    return LibraryLyricsLinkResult(folder: folder);
  }

  Future<void> _markQueuedCopiesWithoutLyrics(String audioPath) async {
    final song = _key(audioPath);
    for (final item in playbackSession.currentState.queue) {
      if (item.isRemoteStream ||
          item.projectId != null ||
          !item.hasLyrics ||
          _key(item.audioAsset.originalPath) != song) {
        continue;
      }
      await playbackSession.updateItem(item.copyWith(hasLyrics: false));
    }
  }

  static String? _parentOf(String path) {
    final slash = path.lastIndexOf(RegExp(r'[\\/]'));
    if (slash <= 0) return null;
    return path.substring(0, slash);
  }
}

/// A song without lyrics, with what the library knows about it.
class _Candidate {
  _Candidate(
    this.entry,
    this.override,
    this.project, {
    required this.dismissed,
  });

  final LocalMediaLibraryEntry entry;
  final LocalMediaMetadata? override;

  /// Canonical paths of lyric files the user unpaired from this song.
  final Set<String> dismissed;

  /// A project for this audio that has no lyrics yet; filled, not replaced.
  final ProjectManifest? project;

  late final LibraryLyricSong song = LibraryLyricSong(
    audioPath: entry.sourcePath,
    title: _titleOf(entry, override),
    artist: _artistOf(entry, override),
  );

  String? get album {
    final embedded = entry.embeddedAlbum;
    return _clean(override?.resolvedAlbum(embedded) ?? embedded);
  }

  String? get artworkPath {
    final embedded = entry.embeddedArtworkPath;
    return _clean(override?.resolvedArtwork(embedded) ?? embedded);
  }

  Duration? get duration {
    final milliseconds = entry.durationMs;
    return milliseconds == null ? null : Duration(milliseconds: milliseconds);
  }

  static String _titleOf(
    LocalMediaLibraryEntry entry,
    LocalMediaMetadata? override,
  ) {
    final embedded = _clean(entry.embeddedTitle);
    final fallback =
        embedded ?? LibraryLyricFileMatcher.fileStem(entry.sourcePath);
    return _clean(override?.resolvedTitle(fallback)) ?? fallback;
  }

  static String? _artistOf(
    LocalMediaLibraryEntry entry,
    LocalMediaMetadata? override,
  ) {
    final embedded = entry.embeddedArtist;
    return _clean(override?.resolvedArtist(embedded) ?? embedded);
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
