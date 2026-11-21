/// A piece of the managed speech recognition environment that is downloaded
/// and replaced as a whole (D-048).
///
/// The runtime managers check each of these on their own: a Whisper model
/// that is present is reused even when the runtime bundle beside it is
/// missing. Merging two copies of the environment therefore works unit by
/// unit, never file by file, so a bundle is never mixed with the state files
/// of another bundle.
enum AsrRuntimeUnit {
  /// The Qwen3-ASR / whisper.cpp bundle with its build revision, readiness
  /// markers and health record.
  runtime,

  /// The standalone whisper.cpp release the Windows fallback installs in
  /// `whisper/<release>` when the bundle has no Whisper of its own.
  whisperRuntime,

  /// The FFmpeg used to normalise audio.
  ffmpeg,

  /// Whisper large-v3 (`ggml-large-v3.bin`, about 3 GB).
  whisperModel,

  /// Qwen3-ASR 1.7B, the model of the RTX high-quality profile.
  qwenAsrLarge,

  /// Qwen3-ASR 0.6B, the model of the Intel Mac profile.
  qwenAsrSmall,

  /// Qwen3 ForcedAligner 0.6B, used for word timing.
  forcedAligner,
}

/// Why a folder is reported as a leftover copy of the environment.
enum AsrRuntimeLeftoverKind {
  /// A `LyricForge/ASRRuntime` folder below the environment in use.
  ///
  /// A build of 2026-10-31 (PR #269) turned a picked `ASRRuntime` folder into
  /// the parent of a new one, so the pointer ended at
  /// `…\ASRRuntime\LyricForge\ASRRuntime` and downloads started again there.
  /// Later builds stopped doing that but left the folder in place.
  nestedCopy,

  /// The environment in use is itself such a nested folder; cleaning moves
  /// its components back into the outer `ASRRuntime` and uses that.
  activeIsNested,

  /// The environment at the default location while another one is in use,
  /// for example after an existing download on another disk was adopted.
  defaultCopy,

  /// A half-finished copy left by a storage move that failed.
  migrationStaging,
}

/// A folder that holds another copy, or part of a copy, of the environment.
class AsrRuntimeLeftover {
  final String path;
  final AsrRuntimeLeftoverKind kind;
  final int bytes;
  final int files;

  /// Units complete in this folder but missing or incomplete in the
  /// environment in use. For a nested copy cleaning moves them over first,
  /// on the same disk, so nothing is downloaded again.
  final List<AsrRuntimeUnit> missingInActive;

  const AsrRuntimeLeftover({
    required this.path,
    required this.kind,
    required this.bytes,
    required this.files,
    this.missingInActive = const [],
  });

  /// Only empty folders: an older build created the layout and nothing was
  /// downloaded into it.
  bool get isEmpty => files == 0;

  /// Cleaning moves this folder's useful units into the environment in use
  /// instead of leaving them behind.
  bool get mergesIntoActive =>
      kind == AsrRuntimeLeftoverKind.nestedCopy ||
      kind == AsrRuntimeLeftoverKind.activeIsNested;

  /// Cleaning deletes this folder. A copy elsewhere (on another disk) is
  /// only deleted when it has nothing the environment in use is missing:
  /// moving gigabytes across disks is a migration, not a clean-up.
  bool get removable =>
      kind != AsrRuntimeLeftoverKind.defaultCopy || missingInActive.isEmpty;
}

/// What a clean-up of leftover copies did.
class AsrRuntimeCleanupResult {
  /// The environment in use afterwards.
  final String activeRoot;

  /// Units moved from a nested copy into [activeRoot].
  final List<AsrRuntimeUnit> movedUnits;

  /// Folders deleted.
  final List<String> removedPaths;

  /// Bytes those folders held.
  final int freedBytes;

  /// Folders kept, because they hold something the environment in use does
  /// not have or because a file in them could not be moved or deleted (for
  /// example while a recognition program from it is still running).
  final List<String> retainedPaths;

  const AsrRuntimeCleanupResult({
    required this.activeRoot,
    this.movedUnits = const [],
    this.removedPaths = const [],
    this.freedBytes = 0,
    this.retainedPaths = const [],
  });

  /// Something on disk changed.
  bool get changed => movedUnits.isNotEmpty || removedPaths.isNotEmpty;
}
