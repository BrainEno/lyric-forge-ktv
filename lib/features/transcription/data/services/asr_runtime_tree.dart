import 'dart:io';

import '../../domain/models/asr_runtime_leftovers.dart';

/// Joins [parts] below [base] with the platform separator.
String asrJoinPath(String base, List<String> parts) {
  var current = base;
  for (final part in parts) {
    current = current.endsWith(Platform.pathSeparator)
        ? '$current$part'
        : '$current${Platform.pathSeparator}$part';
  }
  return current;
}

/// The on-disk layout of one `ASRRuntime` folder, read unit by unit (D-048).
///
/// The paths are the ones the runtime managers write:
/// `ResilientAsrRuntimeManager` puts its standalone Whisper in `whisper/`,
/// `ManagedAsrRuntimeManager` puts the bundle in `bundle/`, FFmpeg in
/// `ffmpeg/`, the Whisper model in `models/whisper/` and the bundle's state
/// in `state/`; `ManagedModelAsrRuntimeManager` puts each Qwen model in
/// `models/qwen/<id with -- for />`. A unit is complete when the file the
/// managers look for first is there; their own size and SHA-256 checks still
/// run before anything is used, so this only decides which copy to keep.
class AsrRuntimeTree {
  AsrRuntimeTree(Directory root) : root = root.absolute;

  final Directory root;

  static const List<String> whisperModel = [
    'models',
    'whisper',
    'ggml-large-v3.bin',
  ];
  static const List<String> revisionFile = [
    'state',
    'runtime-build-revision.txt',
  ];
  static const List<String> healthFile = ['.runtime-health-v1.json'];

  /// Where `ResilientAsrRuntimeManager` unpacks the standalone whisper.cpp
  /// release, one folder per release tag.
  static const List<String> whisperRuntime = ['whisper'];

  /// The folder name of each Qwen model below `models/qwen`.
  static const Map<AsrRuntimeUnit, String> qwenModelDirectories = {
    AsrRuntimeUnit.qwenAsrLarge: 'Qwen--Qwen3-ASR-1.7B',
    AsrRuntimeUnit.qwenAsrSmall: 'Qwen--Qwen3-ASR-0.6B',
    AsrRuntimeUnit.forcedAligner: 'Qwen--Qwen3-ForcedAligner-0.6B',
  };

  String path(List<String> parts) => asrJoinPath(root.path, parts);

  /// Every unit that is complete here.
  Future<Set<AsrRuntimeUnit>> completeUnits() async {
    final units = <AsrRuntimeUnit>{};
    for (final unit in AsrRuntimeUnit.values) {
      if (await isComplete(unit)) units.add(unit);
    }
    return units;
  }

  /// Whether [unit] is complete here. An unreadable folder counts as
  /// missing rather than failing the caller.
  Future<bool> isComplete(AsrRuntimeUnit unit) async {
    try {
      return switch (unit) {
        AsrRuntimeUnit.runtime => await _anyFile(const [
          ['bundle', 'bin', 'whisper-cli'],
          ['bundle', 'bin', 'whisper-cli.exe'],
          ['bundle', 'bin', 'qwen3-asr'],
          ['bundle', 'bin', 'qwen3-asr.exe'],
        ]),
        AsrRuntimeUnit.whisperRuntime => await _containsFile(
          Directory(path(whisperRuntime)),
          const {'whisper-cli', 'whisper-cli.exe'},
        ),
        AsrRuntimeUnit.ffmpeg => await _anyFile(const [
          ['ffmpeg', 'bin', 'ffmpeg'],
          ['ffmpeg', 'bin', 'ffmpeg.exe'],
        ]),
        AsrRuntimeUnit.whisperModel => await File(path(whisperModel)).exists(),
        AsrRuntimeUnit.qwenAsrLarge ||
        AsrRuntimeUnit.qwenAsrSmall ||
        AsrRuntimeUnit.forcedAligner => await _completeQwenModel(
          Directory(
            path(['models', 'qwen', qwenModelDirectories[unit]!]),
          ),
        ),
      };
    } on FileSystemException {
      return false;
    }
  }

  /// The paths, relative to the root, that make up [unit] here and in
  /// [other]. The runtime's readiness markers are named after the hardware
  /// profile, so their names are read from both folders.
  Future<List<List<String>>> pieces(
    AsrRuntimeUnit unit, {
    AsrRuntimeTree? other,
  }) async {
    switch (unit) {
      case AsrRuntimeUnit.runtime:
        final markers = <String>{
          ...await _readyMarkers(),
          if (other != null) ...await other._readyMarkers(),
        }.toList()..sort();
        return [
          const ['bundle'],
          revisionFile,
          healthFile,
          for (final name in markers) ['state', name],
        ];
      case AsrRuntimeUnit.whisperRuntime:
        return const [whisperRuntime];
      case AsrRuntimeUnit.ffmpeg:
        return const [
          ['ffmpeg'],
        ];
      case AsrRuntimeUnit.whisperModel:
        return const [
          whisperModel,
          ['models', 'whisper', 'ggml-large-v3.bin.part'],
        ];
      case AsrRuntimeUnit.qwenAsrLarge:
      case AsrRuntimeUnit.qwenAsrSmall:
      case AsrRuntimeUnit.forcedAligner:
        return [
          ['models', 'qwen', qwenModelDirectories[unit]!],
        ];
    }
  }

  /// Whether any piece of [unit] exists here, complete or not.
  Future<bool> hasAny(AsrRuntimeUnit unit) async {
    for (final piece in await pieces(unit)) {
      if (await _exists(path(piece))) return true;
    }
    return false;
  }

  /// The build revision the runtime bundle here was installed from.
  Future<({String revision, DateTime modified})?> runtimeRevision() async {
    final file = File(path(revisionFile));
    try {
      if (!await file.exists()) return null;
      return (
        revision: (await file.readAsString()).trim(),
        modified: await file.lastModified(),
      );
    } on FileSystemException {
      return null;
    }
  }

  Future<bool> _anyFile(List<List<String>> candidates) async {
    for (final candidate in candidates) {
      if (await File(path(candidate)).exists()) return true;
    }
    return false;
  }

  /// Whether a file named one of [names] lies anywhere below [directory],
  /// the way the resilient manager looks for its Whisper executable.
  Future<bool> _containsFile(Directory directory, Set<String> names) async {
    if (!await directory.exists()) return false;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last.toLowerCase();
      if (names.contains(name)) return true;
    }
    return false;
  }

  Future<bool> _completeQwenModel(Directory directory) async {
    if (!await directory.exists()) return false;
    if (await File(
      asrJoinPath(directory.path, ['.lyricforge-model.json']),
    ).exists()) {
      return true;
    }
    if (!await File(asrJoinPath(directory.path, ['config.json'])).exists()) {
      return false;
    }
    await for (final child in directory.list(followLinks: false)) {
      if (child is File && child.path.endsWith('.safetensors')) return true;
    }
    return false;
  }

  Future<List<String>> _readyMarkers() async {
    final state = Directory(path(const ['state']));
    final names = <String>[];
    try {
      if (!await state.exists()) return names;
      await for (final entity in state.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.startsWith('qwen_') && name.endsWith('.ready.json')) {
          names.add(name);
        }
      }
    } on FileSystemException {
      return names;
    }
    return names;
  }
}

Future<bool> _exists(String path) async =>
    await FileSystemEntity.type(path, followLinks: false) !=
    FileSystemEntityType.notFound;

/// What merging one `ASRRuntime` folder into another did.
class AsrRuntimeMergeOutcome {
  /// Complete units that moved into the target.
  final List<AsrRuntimeUnit> movedUnits;

  /// Pieces that could not move, with the reason.
  final List<String> failures;

  const AsrRuntimeMergeOutcome({
    this.movedUnits = const [],
    this.failures = const [],
  });

  static const AsrRuntimeMergeOutcome none = AsrRuntimeMergeOutcome();
}

/// Moves what one copy of the environment has and another lacks into the
/// other, by renaming on the same disk (D-048).
///
/// Nothing is copied and nothing is deleted. For each unit:
/// - complete in the source but not in the target: the source's pieces move
///   in, and whatever partial pieces the target had move out to where the
///   source's were, so they stay on disk as part of the leftover copy;
/// - complete in both: the target's is kept, except a runtime bundle from a
///   newer build, which takes the place of the older one the same way;
/// - incomplete in both but absent from the target: the source's partial
///   pieces move in, so a download can resume instead of starting over.
///
/// A piece that cannot move (on Windows, a folder whose program is still
/// running) is reported and the rest carries on; a failed exchange is undone
/// so neither copy loses its piece.
class AsrRuntimeTreeMerger {
  const AsrRuntimeTreeMerger();

  Future<AsrRuntimeMergeOutcome> merge({
    required Directory from,
    required Directory into,
  }) async {
    final source = AsrRuntimeTree(from);
    final target = AsrRuntimeTree(into);
    if (!await source.root.exists()) return AsrRuntimeMergeOutcome.none;
    await target.root.create(recursive: true);

    final moved = <AsrRuntimeUnit>[];
    final failures = <String>[];
    final holding = Directory(
      target.path([
        '.lyricforge-merge-${DateTime.now().microsecondsSinceEpoch}',
      ]),
    );
    try {
      for (final unit in AsrRuntimeUnit.values) {
        final take = await _takes(unit, source: source, target: target);
        if (take == null) continue;
        final pieces = await source.pieces(unit, other: target);
        var complete = true;
        for (final (index, piece) in pieces.indexed) {
          try {
            await _exchange(
              source.path(piece),
              target.path(piece),
              holding: asrJoinPath(holding.path, ['${unit.name}-$index']),
            );
          } on FileSystemException catch (error) {
            complete = false;
            failures.add('${source.path(piece)}：${error.message}');
          }
        }
        if (take && complete) moved.add(unit);
      }
      await _moveResumeFiles(source, target, failures);
    } finally {
      await _removeIfEmpty(holding);
    }
    return AsrRuntimeMergeOutcome(movedUnits: moved, failures: failures);
  }

  /// Null to keep the target's [unit]; true when a complete unit moves in;
  /// false when only partial pieces move in.
  Future<bool?> _takes(
    AsrRuntimeUnit unit, {
    required AsrRuntimeTree source,
    required AsrRuntimeTree target,
  }) async {
    final sourceComplete = await source.isComplete(unit);
    final targetComplete = await target.isComplete(unit);
    if (sourceComplete && !targetComplete) return true;
    if (sourceComplete && targetComplete) {
      if (unit != AsrRuntimeUnit.runtime) return null;
      return await _newerRuntime(source, target) ? true : null;
    }
    if (!sourceComplete &&
        !targetComplete &&
        await source.hasAny(unit) &&
        !await target.hasAny(unit)) {
      return false;
    }
    return null;
  }

  /// The source's bundle comes from a different, later installed build.
  Future<bool> _newerRuntime(
    AsrRuntimeTree source,
    AsrRuntimeTree target,
  ) async {
    final from = await source.runtimeRevision();
    if (from == null) return false;
    final into = await target.runtimeRevision();
    if (into == null) return true;
    if (from.revision == into.revision) return false;
    return from.modified.isAfter(into.modified);
  }

  /// Puts [sourcePath] at [targetPath] and whatever was at [targetPath] at
  /// [sourcePath].
  Future<void> _exchange(
    String sourcePath,
    String targetPath, {
    required String holding,
  }) async {
    final sourceExists = await _exists(sourcePath);
    final targetExists = await _exists(targetPath);
    if (!sourceExists && !targetExists) return;
    if (!targetExists) {
      await _rename(sourcePath, targetPath);
      return;
    }
    if (!sourceExists) {
      await _rename(targetPath, sourcePath);
      return;
    }
    await _rename(targetPath, holding);
    try {
      await _rename(sourcePath, targetPath);
    } on FileSystemException {
      await _rename(holding, targetPath);
      rethrow;
    }
    await _rename(holding, sourcePath);
  }

  /// Partial downloads of the source the target does not have.
  Future<void> _moveResumeFiles(
    AsrRuntimeTree source,
    AsrRuntimeTree target,
    List<String> failures,
  ) async {
    final downloads = Directory(source.path(const ['downloads']));
    if (!await downloads.exists()) return;
    final names = <String>[];
    await for (final entity in downloads.list(followLinks: false)) {
      final name = entity.uri.pathSegments.last;
      if (entity is File && name.endsWith('.part')) names.add(name);
    }
    for (final name in names) {
      final into = target.path(['downloads', name]);
      if (await _exists(into)) continue;
      try {
        await _rename(source.path(['downloads', name]), into);
      } on FileSystemException catch (error) {
        failures.add('${source.path(['downloads', name])}：${error.message}');
      }
    }
  }

  Future<void> _rename(String from, String to) async {
    await Directory(to).parent.create(recursive: true);
    final type = await FileSystemEntity.type(from, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('找不到要移动的文件', from);
    } else if (type == FileSystemEntityType.directory) {
      await Directory(from).rename(to);
    } else if (type == FileSystemEntityType.link) {
      await Link(from).rename(to);
    } else {
      await File(from).rename(to);
    }
  }

  Future<void> _removeIfEmpty(Directory directory) async {
    try {
      if (!await directory.exists()) return;
      if (await directory.list().isEmpty) await directory.delete();
    } on FileSystemException {
      // A holding folder that is not empty keeps a piece an exchange could
      // not put back; leaving it is what keeps that piece.
      return;
    }
  }
}
