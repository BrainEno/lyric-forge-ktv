import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/models/project_manifest.dart';
import '../../domain/repositories/project_repository.dart';

/// File-backed project repository used by the desktop app.
///
/// The repository lazily restores all manifests from a single JSON document and
/// rewrites it through a temporary file after every mutation. This keeps the
/// existing repository contract while making projects survive app restarts.
class FileProjectRepository implements ProjectRepository {
  final Directory? rootDirectory;

  final Map<String, ProjectManifest> _projects = <String, ProjectManifest>{};
  Future<void>? _loadFuture;
  Future<void> _writeChain = Future<void>.value();

  FileProjectRepository({this.rootDirectory});

  Future<void> _ensureLoaded() => _loadFuture ??= _load();

  Future<Directory> _dataDirectory() async {
    if (rootDirectory != null) {
      await rootDirectory!.create(recursive: true);
      return rootDirectory!;
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      support.path +
          Platform.pathSeparator +
          'LyricForge' +
          Platform.pathSeparator +
          'Data',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _storeFile() async {
    final directory = await _dataDirectory();
    return File(directory.path + Platform.pathSeparator + 'projects.json');
  }

  Future<void> _load() async {
    final file = await _storeFile();
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

  Future<void> _persist() async {
    final snapshot = _projects.values
        .map((project) => project.toJson())
        .toList(growable: false);

    _writeChain = _writeChain.then((_) async {
      final file = await _storeFile();
      final temporary = File(file.path + '.tmp');
      await temporary.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'projects': snapshot,
        }),
        flush: true,
      );
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    });
    await _writeChain;
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
    final updated = project.copyWith(updatedAt: DateTime.now());
    _projects[project.id] = updated;
    await _persist();
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
