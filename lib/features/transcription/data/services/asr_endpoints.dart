/// Every network address the transcription feature downloads from or probes.
///
/// Model weights, runtime bundles, release metadata and the proxy probe used
/// to be built from URL literals spread over five services, with the project
/// owner hard-coded twice. A mirror switch or a fork then had to find all of
/// them, and missing one sent part of an install to the old address. This is
/// now the only file under `lib/features/transcription` allowed to spell out
/// a host (an architecture test keeps it that way); services ask it for a
/// [Uri] by meaning — "this Hugging Face file", "that release asset".
///
/// What is pinned (release tags, file names, SHA-256 sums) stays next to the
/// code that verifies it; only *where* to fetch it lives here.
abstract final class AsrEndpoints {
  /// `owner/name` of the repository whose GitHub releases carry the managed
  /// ASR runtime bundles. A fork that publishes its own bundles builds with
  /// `--dart-define=LYRICFORGE_RELEASE_REPOSITORY=owner/name`.
  static const String releaseRepository = String.fromEnvironment(
    'LYRICFORGE_RELEASE_REPOSITORY',
    defaultValue: 'BrainEno/lyric-forge-ktv',
  );

  static const String huggingFaceHost = 'huggingface.co';
  static const String modelScopeHost = 'modelscope.cn';
  static const String _gitHub = 'https://github.com';
  static const String _gitHubApi = 'https://api.github.com';

  /// Hugging Face repository of the ggml Whisper weights.
  static const String whisperGgmlModelRepository = 'ggerganov/whisper.cpp';

  /// Release download roots of the pinned third-party FFmpeg builds. They
  /// are compile-time constants so the pinned release table can stay `const`.
  static const String btbnFfmpegReleaseDownloads =
      '$_gitHub/BtbN/FFmpeg-Builds/releases/download';
  static const String boul2gomFfmpegReleaseDownloads =
      '$_gitHub/boul2gom/ffmpeg-builds/releases/download';

  static const String _whisperCppRepository = 'ggml-org/whisper.cpp';

  /// [fileName] of the `main` revision of Hugging Face repository [modelId].
  static Uri huggingFaceFile(String modelId, String fileName) => Uri.parse(
    'https://$huggingFaceHost/$modelId/resolve/main/$fileName?download=true',
  );

  /// The ggml Whisper weights file [fileName], e.g. `ggml-large-v3.bin`.
  static Uri whisperGgmlModel(String fileName) =>
      huggingFaceFile(whisperGgmlModelRepository, fileName);

  /// File listing of ModelScope repository [modelId], recursively, at
  /// `master`.
  static Uri modelScopeManifest(String modelId) => Uri.https(
    modelScopeHost,
    '/api/v1/models/$modelId/repo/files',
    const {'Revision': 'master', 'Recursive': 'true'},
  );

  /// [fileName] of the `master` revision of ModelScope repository [modelId].
  static Uri modelScopeFile(String modelId, String fileName) => Uri.https(
    modelScopeHost,
    '/models/$modelId/resolve/master/$fileName',
  );

  /// Asset [assetName] of release [tag] of [releaseRepository].
  static Uri runtimeReleaseAsset(String tag, String assetName) =>
      _releaseAsset(releaseRepository, tag, assetName);

  /// GitHub API description of release [tag] of [releaseRepository], which
  /// lists the size and digest of every asset.
  static Uri runtimeReleaseMetadata(String tag) =>
      Uri.parse('$_gitHubApi/repos/$releaseRepository/releases/tags/$tag');

  /// Asset [assetName] of the upstream whisper.cpp release [tag].
  static Uri whisperCppReleaseAsset(String tag, String assetName) =>
      _releaseAsset(_whisperCppRepository, tag, assetName);

  /// The address used to ask the platform which proxy downloads go through.
  /// Model downloads are the largest transfers, so their host is the probe.
  static Uri get proxyProbe => Uri.https(huggingFaceHost, '/');

  static Uri _releaseAsset(String repository, String tag, String assetName) =>
      Uri.parse('$_gitHub/$repository/releases/download/$tag/$assetName');
}
