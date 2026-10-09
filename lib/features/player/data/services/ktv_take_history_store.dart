import 'dart:convert';
import 'dart:io';

import '../../../project/domain/models/project_manifest.dart';
import '../../domain/models/ktv_recording_session.dart';

/// Discovers existing takes without mutating their original audio or manifests.
class KtvTakeHistoryStore {
  const KtvTakeHistoryStore();

  Future<List<KtvRecordingSession>> listFromDirectory(
    Directory projectDirectory,
    String projectId,
  ) async {
    final root = Directory('${projectDirectory.path}${Platform.pathSeparator}recordings');
    if (!await root.exists()) return const [];
    final takes = <KtvRecordingSession>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory || entity.path.split(Platform.pathSeparator).last.startsWith('take_') == false) continue;
      final manifest = File('${entity.path}${Platform.pathSeparator}session.json');
      if (!await manifest.exists()) continue;
      try {
        final decoded = jsonDecode(await manifest.readAsString());
        if (decoded is! Map<String, dynamic>) continue;
        final take = KtvRecordingSession.fromJson(decoded);
        if (take.projectId != projectId || take.completedAt == null) continue;
        // Never trust paths in a manifest when listing a project's recordings.
        if (!_inside(entity, File(take.micStemPath)) ||
            !_inside(entity, File(take.manifestPath)) ||
            !await File(take.micStemPath).exists()) continue;
        takes.add(take);
      } catch (_) {
        // One corrupt or interrupted take must not hide the remaining history.
      }
    }
    takes.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return List.unmodifiable(takes);
  }

  bool _inside(Directory directory, File file) {
    final root = directory.absolute.path;
    final path = file.absolute.path;
    return path.startsWith('$root${Platform.pathSeparator}');
  }
}
