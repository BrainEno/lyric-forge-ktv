import '../models/project_manifest.dart';

/// Why a [ProjectDuplicateGroup] was put together (D-063).
enum ProjectDuplicateReason {
  /// The projects were made from the same audio file.
  sameAudio,

  /// Same title and artist and the same length: the same song imported from
  /// two copies of the file.
  sameSong,
}

/// Projects that are one song more than once, the one worth keeping first.
class ProjectDuplicateGroup {
  const ProjectDuplicateGroup(this.projects, this.reason);

  /// At least two; [keep] first, then the others in the same order.
  final List<ProjectManifest> projects;
  final ProjectDuplicateReason reason;

  ProjectManifest get keep => projects.first;
  List<ProjectManifest> get extras => projects.sublist(1);
}

/// Finds lyric projects that were created more than once for one song.
///
/// A batch import used to create a new project whenever a song came through
/// the queue again (after its finished entry had been cleared), so one song
/// could end up with several recognition projects. Projects made from the
/// same audio file are certainly duplicates; projects with the same title,
/// artist and length (both lengths known) are the same song in two files.
class ProjectDuplicateFinder {
  const ProjectDuplicateFinder({
    this.canonicalize = _identity,
    this.lengthTolerance = const Duration(seconds: 2),
  });

  /// Turns an audio path into the form two equal paths share (case, `..`).
  final String Function(String path) canonicalize;

  /// How far two lengths may be apart for [ProjectDuplicateReason.sameSong].
  final Duration lengthTolerance;

  static String _identity(String path) => path;

  /// The groups, largest first; projects without a duplicate are left out.
  List<ProjectDuplicateGroup> find(List<ProjectManifest> projects) {
    final parent = List<int>.generate(projects.length, (index) => index);
    int root(int index) {
      var current = index;
      while (parent[current] != current) {
        parent[current] = parent[parent[current]];
        current = parent[current];
      }
      return current;
    }

    final sameAudio = <int>{};
    void join(int a, int b, {required bool audio}) {
      final ra = root(a);
      final rb = root(b);
      if (audio) sameAudio.addAll([a, b]);
      if (ra != rb) parent[rb] = ra;
    }

    final byAudio = <String, int>{};
    final bySong = <String, List<int>>{};
    for (var index = 0; index < projects.length; index++) {
      final project = projects[index];
      final audio = audioKey(project);
      if (audio != null) {
        final first = byAudio[audio];
        if (first == null) {
          byAudio[audio] = index;
        } else {
          join(first, index, audio: true);
        }
      }
      final song = songKey(project);
      if (song != null) (bySong[song] ??= []).add(index);
    }
    for (final indices in bySong.values) {
      for (var i = 0; i < indices.length; i++) {
        for (var j = i + 1; j < indices.length; j++) {
          final a = projects[indices[i]].audioAsset?.duration;
          final b = projects[indices[j]].audioAsset?.duration;
          if (a == null || b == null) continue;
          if ((a - b).abs() <= lengthTolerance) {
            join(indices[i], indices[j], audio: false);
          }
        }
      }
    }

    final members = <int, List<int>>{};
    for (var index = 0; index < projects.length; index++) {
      (members[root(index)] ??= []).add(index);
    }
    final groups = <ProjectDuplicateGroup>[
      for (final indices in members.values)
        if (indices.length > 1)
          ProjectDuplicateGroup(
            [for (final index in indices) projects[index]]..sort(compareKeep),
            indices.any(sameAudio.contains)
                ? ProjectDuplicateReason.sameAudio
                : ProjectDuplicateReason.sameSong,
          ),
    ];
    groups.sort((a, b) {
      final bySize = b.projects.length.compareTo(a.projects.length);
      return bySize != 0 ? bySize : a.keep.name.compareTo(b.keep.name);
    });
    return groups;
  }

  /// The canonical audio path of [project], or null without audio.
  String? audioKey(ProjectManifest project) {
    final path = project.audioAsset?.originalPath.trim() ?? '';
    return path.isEmpty ? null : canonicalize(path);
  }

  /// Normalised `title|artist`, or null without a title.
  static String? songKey(ProjectManifest project) {
    final title = _normalise(project.name);
    if (title.isEmpty) return null;
    return '$title|${_normalise(project.artist ?? '')}';
  }

  static String _normalise(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '');

  /// Orders the project worth keeping first: one with lyrics, then the one
  /// furthest along (edited lyrics beat a fresh draft), then the one with
  /// more lines, then the most recently changed.
  static int compareKeep(ProjectManifest a, ProjectManifest b) {
    final lyrics = _flag(b.hasLyrics).compareTo(_flag(a.hasLyrics));
    if (lyrics != 0) return lyrics;
    final stage = b.currentStage.index.compareTo(a.currentStage.index);
    if (stage != 0) return stage;
    final lines = (b.lyricDocument?.lines.length ?? 0).compareTo(
      a.lyricDocument?.lines.length ?? 0,
    );
    if (lines != 0) return lines;
    final updated = b.updatedAt.compareTo(a.updatedAt);
    return updated != 0 ? updated : a.id.compareTo(b.id);
  }

  static int _flag(bool value) => value ? 1 : 0;

  /// Why [group]'s first project is the one kept, for the confirmation.
  static String keepReason(ProjectDuplicateGroup group) {
    final keep = group.keep;
    final next = group.projects[1];
    if (keep.hasLyrics && !next.hasLyrics) return '只有它有歌词';
    if (keep.currentStage.index > next.currentStage.index) {
      return keep.currentStage == ProcessingStage.lyricsEdited ||
              keep.currentStage == ProcessingStage.exported
          ? '歌词校对过'
          : '进度最靠后';
    }
    if ((keep.lyricDocument?.lines.length ?? 0) >
        (next.lyricDocument?.lines.length ?? 0)) {
      return '歌词行数最多';
    }
    return '最近修改';
  }
}
