import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/spacing_tokens.dart';
import '../../../transcription/domain/models/transcription_models.dart';
import '../../../transcription/presentation/transcription_screen_dependencies.dart';
import '../../../transcription/presentation/widgets/asr_existing_model_actions.dart';
import '../../../transcription/presentation/widgets/transcription_config_dialog.dart';
import 'ai_transcription_settings_cards.dart';
import 'ai_transcription_settings_controller.dart';

/// 设置 → 本地识别.
///
/// The four cards are stateless (ai_transcription_settings_cards.dart) and
/// the install, pause, existing-model, storage-move and delete flows live in
/// [AiTranscriptionSettingsController] (audit C-03). This widget owns what
/// needs a [BuildContext]: the confirmation dialogs, the folder picker, the
/// path dialog, the advanced settings dialog and the snack bar after a move.
class AiTranscriptionSettingsSection extends StatefulWidget {
  final AsrRuntimeSetupDependencies dependencies;

  const AiTranscriptionSettingsSection({super.key, required this.dependencies});

  @override
  State<AiTranscriptionSettingsSection> createState() =>
      _AiTranscriptionSettingsSectionState();
}

class _AiTranscriptionSettingsSectionState
    extends State<AiTranscriptionSettingsSection> {
  late final AiTranscriptionSettingsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AiTranscriptionSettingsController(
      settingsStore: widget.dependencies.transcriptionSettingsStore,
      runtimeManager: widget.dependencies.asrRuntimeManager,
      storagePreflightService: widget.dependencies.asrStoragePreflightService,
      managedStorageService: widget.dependencies.asrManagedStorageService,
      texts: AsrExistingModelTexts(
        scanning: AsrFolderText.scanning,
        notFound: AsrFolderText.notFound,
        pathNotRecognised: AsrFolderText.pathNotRecognised,
        checkingPath: AsrFolderText.checkingPath,
      ),
    )..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteExistingModelPath() async {
    if (!_controller.canStartExclusive) return;
    final path = await showAsrExistingModelPathDialog(context);
    if (path == null || path.trim().isEmpty || !mounted) return;
    await _controller.adoptExistingPath(path);
  }

  Future<void> _browseExistingModel() async {
    if (!_controller.canStartExclusive) return;
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: AsrFolderText.pickExistingTitle,
    );
    if (path == null || path.trim().isEmpty || !mounted) return;
    await _controller.adoptExistingPath(path);
  }

  Future<void> _changeManagedStorageLocation() async {
    final parent = await FilePicker.platform.getDirectoryPath(
      dialogTitle: AsrFolderText.pickNewParentTitle,
    );
    if (parent == null || parent.trim().isEmpty || !mounted) return;
    await _moveManagedStorage(parent: parent);
  }

  Future<void> _restoreDefaultStorageLocation() async {
    await _moveManagedStorage(useDefault: true);
  }

  Future<void> _moveManagedStorage({
    String? parent,
    bool useDefault = false,
  }) async {
    if (!_controller.canStartExclusive) return;
    if (!useDefault && (parent == null || parent.trim().isEmpty)) return;

    final bytes = _controller.managedBytes ?? 0;
    if (bytes > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(useDefault ? '迁回默认位置？' : '迁移识别环境？'),
          content: Text(
            AsrFolderText.moveConfirmation(AsrSettingsText.formatBytes(bytes)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('开始迁移'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    final result = await _controller.moveStorage(
      parent: parent,
      useDefault: useDefault,
    );
    if (!mounted || result == null || !result.moved) return;
    final message = AiTranscriptionSettingsController.movedMessage(result);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deleteModels({required bool reinstall}) async {
    if (_controller.status == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(reinstall ? '删除并重新安装模型？' : '删除本地模型？'),
        content: Text(
          reinstall
              ? '会删除 Elysium Player 托管的 Qwen / Whisper 模型，然后按当前质量方案重新下载。手工指定的外部模型不会被删除。'
              : '会删除 Elysium Player 托管的 Qwen / Whisper 模型。runtime 与手工指定的外部模型会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(reinstall ? '删除并重装' : '删除模型'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _controller.deleteModels(reinstall: reinstall);
  }

  Future<void> _openAdvanced() async {
    final updated = await showDialog<TranscriptionConfig>(
      context: context,
      builder: (context) => TranscriptionConfigDialog(
        initialConfig: _controller.config,
        dependencies: widget.dependencies.configDialogDependencies,
      ),
    );
    if (updated == null || !mounted) return;
    await _controller.save(updated);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _buildCards(_controller),
    );
  }

  Widget _buildCards(AiTranscriptionSettingsController state) {
    final busy = state.busy;
    VoidCallback? unlessBusy(VoidCallback action) => busy ? null : action;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AsrPlanCard(
          config: state.config,
          status: state.status,
          loading: state.loading,
          installing: state.installing,
          managedBytes: state.managedBytes,
          onModeChanged: busy
              ? null
              : (mode) => unawaited(state.changeMode(mode)),
        ),
        const SizedBox(height: AppSpacing.lg),
        AsrStorageSettingsCard(
          ready: state.ready,
          loading: state.loading,
          storage: state.storage,
          location: state.managedStorageLocation,
          scanningExisting: state.scanningExisting,
          existingModelMessage: state.existingModelMessage,
          movingStorage: state.movingStorage,
          movingCopiedBytes: state.movingCopiedBytes,
          movingTotalBytes: state.movingTotalBytes,
          onScan: unlessBusy(state.scanExisting),
          onPastePath: unlessBusy(_pasteExistingModelPath),
          onBrowse: unlessBusy(_browseExistingModel),
          onChangeLocation: unlessBusy(_changeManagedStorageLocation),
          onRestoreDefault: unlessBusy(_restoreDefaultStorageLocation),
        ),
        const SizedBox(height: AppSpacing.lg),
        AsrMaintenanceCard(
          ready: state.ready,
          loading: state.loading,
          busy: busy,
          storageBlocked: state.storageBlocked,
          installing: state.installing,
          paused: state.paused,
          progress: state.progress,
          error: state.error,
          failedComponent: state.failedComponent,
          onRefresh: () => state.refresh(loadFromStore: true),
          onInstall: state.install,
          onPause: state.pause,
          onResume: state.resume,
          onRetry: state.retry,
          onDelete: (reinstall) => _deleteModels(reinstall: reinstall),
        ),
        const SizedBox(height: AppSpacing.lg),
        AsrAdvancedSettingsCard(
          config: state.config,
          onOpenAdvanced: unlessBusy(_openAdvanced),
        ),
      ],
    );
  }
}
