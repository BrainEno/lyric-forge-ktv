import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../core/persistence/atomic_json_file.dart';

import 'package:path_provider/path_provider.dart';

import '../../../player/domain/repositories/local_media_metadata_repository.dart';
import '../../../player/domain/services/playback_lyrics_project_linker.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../domain/models/project_manifest.dart';
import '../../domain/repositories/project_repository.dart';

/// File-backed project repository used by the desktop app.
///
/// The repository lazily restores all manifests from a single JSON document and
/// rewrites it through a temporary file after every mutation. This keeps the
/// existing repository contract while making projects survive app restarts.
class FileProjectRepository implements ProjectRepository {
  static bool _isValidStoreJson(Object? decoded) =>
      decoded is Map && decoded['projects'] is List;

  final Directory? rootDirectory;
  final LocalMediaMetadataRepository? _mediaMetadataRepository;
  final PlaybackSessionService? _playbackSession;

  final Map<String, ProjectManifest> _projects = <String, ProjectManifest>{};
  Future<void>? _loadFuture;
  Future<void> _writeChain = Future<void>.value();

  FileProjectRepository({
    this.rootDirectory,
    LocalMediaMetadataRepository? mediaMetadataRepository,
    PlaybackSessionService? playbackSession,
  }) : _mediaMetadataRepository = mediaMetadataRepository,
       _playbackSession = playbackSession;

  Future<void> _ensureLoaded() => _loadFuture ??= _load();

  Future<Directory> _dataDirectory() async {
    if (rootDirectory != null) {
      await rootDirectory!.create(recursive: true);
      return rootDirectory!;
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}LyricForge${Platform.pathSeparator}Data',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _storeFile() async {
    final directory = await _dataDirectory();
    return File('${directory.path}${Platform.pathSeparator}projects.json');
  }

  Future<void> _load() async {
    final file = await _storeFile();
    await AtomicJsonFile.recoverIfNeeded(file, validate: _isValidStoreJson);
    if (await file.exists() &&
        !await AtomicJsonFile.isValidJsonFile(
          file,
          validate: _isValidStoreJson,
        )) {
      throw FormatException(
        'The local project store is invalid and no recoverable copy is available. ${file.path}',
      );
    }
    if (!await file.exists()) return;

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final entries = decoded['projects'];
      if (entries is! List) return;

      for (final entry in entries) {
        if (entry is! Map) continue;
        final project = ProjectManifest.fromJson(
          Map<String, dynamic>.from(entry),
        );
        _projects[project.id] = project;
      }
    } catch (error) {
      throw ProjectRepositoryException(
        'Failed to restore local projects',
        cause: error is Exception ? error : Exception(error.toString()),
      );
    }
  }

  Future<void> _persist() {
    final payload = const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'projects': _projects.values
          .map((project) => project.toJson())
          .toList(growable: false),
    });
    final previous = _writeChain;
    final operation = () async {
      // Surface a failed write to the caller that initiated it, but allow later
      // mutations to retry instead of inheriting a permanently failed chain.
      try {
        await previous;
      } catch (_) {}

      final file = await _storeFile();
      await AtomicJsonFile.write(file, payload, validate: _isValidStoreJson);
    }();
    _writeChain = operation;
    return operation;
  }

  @override
  Future<List<ProjectManifest>> getAllProjects() async {
    await _ensureLoaded();
    final projects = _projects.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  @override
  Future<ProjectManifest?> getProjectById(String id) async {
    await _ensureLoaded();
    return _projects[id];
  }

  @override
  Future<ProjectManifest> createProject({
    required String name,
    String? artist,
    String? album,
  }) async {
    await _ensureLoaded();
    final now = DateTime.now();
    var id = now.microsecondsSinceEpoch.toString();
    while (_projects.containsKey(id)) {
      id = (int.parse(id) + 1).toString();
    }
    final project = ProjectManifest(
      id: id,
      name: name,
      artist: artist,
      album: album,
      createdAt: now,
      updatedAt: now,
    );
    _projects[project.id] = project;
    await _persist();
    return project;
  }

  @override
  Future<ProjectManifest> updateProject(ProjectManifest project) async {
    await _ensureLoaded();
    if (!_projects.containsKey(project.id)) {
      throw ProjectRepositoryException('Project not found: ${project.id}');
    }
    final oldProject = _projects[project.id]!;
    final updated = project.copyWith(updatedAt: DateTime.now());
    _projects[project.id] = updated;
    await _persist();

    // Auto-link to local song metadata and the playback queue the very first
    // time lyrics appear, so editor/import saves benefit from the same
    // association the transcription workflow gets.
    final mediaMetadataRepository = _mediaMetadataRepository;
    final playbackSession = _playbackSession;
    final audioAsset = updated.audioAsset;
    if (oldProject.lyricDocument == null &&
        updated.lyricDocument != null &&
        audioAsset != null &&
        mediaMetadataRepository != null &&
        playbackSession != null) {
      unawaited(
        linkPlaybackLyricsProject(
          audioPath: audioAsset.originalPath,
          projectId: updated.id,
          metadataRepository: mediaMetadataRepository,
          playbackSession: playbackSession,
        ),
      );
    }

    return updated;
  }

  @override
  Future<void> deleteProject(String id) async {
    await _ensureLoaded();
    _projects.remove(id);
    await _persist();
  }

  @override
  Future<List<ProjectManifest>> getRecentProjects({int limit = 10}) async {
    final projects = await getAllProjects();
    return projects.take(limit).toList(growable: false);
  }
}
