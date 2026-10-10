from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{path}: expected one match, found {count}: {old[:100]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')

service = 'lib/features/player/data/services/local_ktv_recording_service.dart'
replace_once(
    service,
    '  final Future<Directory> Function(ProjectManifest) _projectDirectoryResolver;\n',
    '  final Future<Directory> Function(ProjectManifest) _projectDirectoryResolver;\n'
    '  final Future<ProcessResult> Function(String, List<String>) _processRunner;\n',
)
replace_once(
    service,
    '    required TranscriptionSettingsStore settingsStore,\n'
    '    Future<Directory> Function(ProjectManifest)? projectDirectoryResolver,\n'
    '  })  : _audioService = audioService,',
    '    required TranscriptionSettingsStore settingsStore,\n'
    '    Future<Directory> Function(ProjectManifest)? projectDirectoryResolver,\n'
    '    Future<ProcessResult> Function(String, List<String>)? processRunner,\n'
    '  })  : _audioService = audioService,',
)
replace_once(
    service,
    '        _settingsStore = settingsStore,\n'
    '        _projectDirectoryResolver = projectDirectoryResolver ??\n'
    '            ((project) => KtvProjectStorage.resolveProjectDirectory(project));',
    '        _settingsStore = settingsStore,\n'
    '        _projectDirectoryResolver = projectDirectoryResolver ??\n'
    '            ((project) => KtvProjectStorage.resolveProjectDirectory(project)),\n'
    '        _processRunner = processRunner ??\n'
    '            ((executable, arguments) =>\n'
    '                Process.run(executable, arguments, runInShell: false));',
)
replace_once(
    service,
    "    if (_state.isRecording) {\n      throw const KtvRecordingException('已经在录音中');\n    }\n",
    "    if (_state.isRecording) {\n      throw const KtvRecordingException('已经在录音中');\n    }\n"
    "    if (_state.isExporting) {\n      throw const KtvRecordingException('混音正在导出，请等待导出完成后再开始录音');\n    }\n",
)
replace_once(
    service,
    "    if (_state.isRecording) {\n      throw const KtvRecordingException('请先停止录音再导出混音');\n    }\n"
    "    if (!session.alignmentReliable) {",
    "    if (_state.isRecording) {\n      throw const KtvRecordingException('请先停止录音再导出混音');\n    }\n"
    "    if (_state.isExporting) {\n      throw const KtvRecordingException('已有混音正在导出，请等待完成后再试');\n    }\n"
    "    if (!session.alignmentReliable) {",
)
replace_once(
    service,
    '        result = await Process.run(ffmpeg, args, runInShell: false);',
    '        result = await _processRunner(ffmpeg, args);',
)
replace_once(
    service,
    '      final exported = session.copyWith(mixedOutputPath: outputPath);\n'
    '      await _writeManifest(exported);',
    '      final latest = await _readLatestSessionForExport(session);\n'
    '      final exported = latest.copyWith(mixedOutputPath: outputPath);\n'
    '      await _writeManifest(exported);',
)
replace_once(
    service,
    '  Future<Directory> _createSessionDirectory(ProjectManifest project) async {',
    r'''  Future<KtvRecordingSession> _readLatestSessionForExport(
    KtvRecordingSession expected,
  ) async {
    final manifest = File(expected.manifestPath);
    if (await FileSystemEntity.type(manifest.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const KtvRecordingException('录音记录已被移动或删除，无法完成混音导出');
    }
    try {
      final decoded = jsonDecode(await manifest.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('session manifest is not an object');
      }
      final latest = KtvRecordingSession.fromJson(decoded);
      if (latest.id != expected.id ||
          latest.projectId != expected.projectId ||
          !_samePath(latest.manifestPath, expected.manifestPath) ||
          !_samePath(latest.micStemPath, expected.micStemPath) ||
          !_samePath(latest.backingPath, expected.backingPath)) {
        throw const KtvRecordingException('录音记录在导出期间发生了身份变化，已取消写入');
      }
      return latest;
    } on KtvRecordingException {
      rethrow;
    } catch (error) {
      throw KtvRecordingException('读取最新录音记录失败，已取消写入：$error');
    }
  }

  bool _samePath(String left, String right) {
    final leftPath = File(left).absolute.path;
    final rightPath = File(right).absolute.path;
    return Platform.isWindows
        ? leftPath.toLowerCase() == rightPath.toLowerCase()
        : leftPath == rightPath;
  }

  Future<Directory> _createSessionDirectory(ProjectManifest project) async {''',
)

player = 'lib/features/player/presentation/screens/player_screen.dart'
# Dynamic guards are deliberately inside the handlers so they remain correct
# even if the history sheet was opened before an export started.
replace_once(
    player,
    '  Future<void> _renameTake(KtvRecordingSession take) async {\n'
    '    final controller = TextEditingController(text: take.displayName ?? \'\');',
    '  Future<void> _renameTake(KtvRecordingSession take) async {\n'
    '    if (_takeMutationLocked()) {\n'
    '      _showTakeMutationLockedMessage();\n'
    '      return;\n'
    '    }\n'
    '    final controller = TextEditingController(text: take.displayName ?? \'\');',
)
replace_once(
    player,
    '  Future<void> _toggleFavoriteTake(KtvRecordingSession take) async {\n'
    '    try {',
    '  Future<void> _toggleFavoriteTake(KtvRecordingSession take) async {\n'
    '    if (_takeMutationLocked()) {\n'
    '      _showTakeMutationLockedMessage();\n'
    '      return;\n'
    '    }\n'
    '    try {',
)
replace_once(
    player,
    '  Future<void> _confirmDeleteTake(KtvRecordingSession take) async {\n'
    '    final confirmed = await showDialog<bool>(',
    '  Future<void> _confirmDeleteTake(KtvRecordingSession take) async {\n'
    '    if (_takeMutationLocked()) {\n'
    '      _showTakeMutationLockedMessage();\n'
    '      return;\n'
    '    }\n'
    '    final confirmed = await showDialog<bool>(',
)
replace_once(
    player,
    '    if (confirmed != true || !mounted) return;\n'
    '    try {\n'
    '      await const KtvTakeHistoryStore().deleteProjectTake(_project, take);',
    '    if (confirmed != true || !mounted) return;\n'
    '    if (_takeMutationLocked()) {\n'
    '      _showTakeMutationLockedMessage();\n'
    '      return;\n'
    '    }\n'
    '    try {\n'
    '      await const KtvTakeHistoryStore().deleteProjectTake(_project, take);',
)
replace_once(
    player,
    '  Future<void> _openTakeHistory() async {\n'
    '    if (_recordingService.currentState.isRecording) return;\n',
    '  bool _takeMutationLocked() {\n'
    '    final state = _recordingService.currentState;\n'
    '    return state.isRecording || state.isExporting;\n'
    '  }\n\n'
    '  void _showTakeMutationLockedMessage() {\n'
    '    if (!mounted) return;\n'
    '    final state = _recordingService.currentState;\n'
    '    ScaffoldMessenger.of(context).showSnackBar(\n'
    '      SnackBar(\n'
    '        content: Text(\n'
    "          state.isExporting\n"
    "              ? '混音正在导出，完成前不能删除、重命名或收藏录音'\n"
    "              : '录音进行中，停止录音后再管理演唱历史',\n"
    '        ),\n'
    '      ),\n'
    '    );\n'
    '  }\n\n'
    '  Future<void> _openTakeHistory() async {\n'
    '    if (_takeMutationLocked()) {\n'
    '      _showTakeMutationLockedMessage();\n'
    '      return;\n'
    '    }\n',
)
