import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_loading_state.dart';
import '../../domain/models/transcription_models.dart';
import '../transcription_screen_dependencies.dart';
import 'asr_existing_model_actions.dart';
import 'asr_install_error_card.dart';
import 'asr_install_progress_card.dart';
import 'asr_runtime_setup_cards.dart';
import 'asr_runtime_setup_controller.dart';
import 'asr_runtime_setup_text.dart';
import 'asr_storage_preflight_card.dart';
import 'transcription_config_dialog.dart';

/// The first-run setup of local lyric recognition: pick a plan, check this
/// computer, reuse an earlier download or fetch what is missing.
///
/// Pops with the ready [TranscriptionConfig] when the user taps 开始使用, or
/// with nothing when the dialog is left before that. It cannot be dismissed
/// while a download runs; the download has to be paused first.
///
/// The flows live in [AsrRuntimeSetupController] and the cards in
/// asr_runtime_setup_cards.dart (audit I-03). This widget keeps what needs a
/// BuildContext: folder pickers, the path and advanced dialogs and the snack
/// bar.
class AsrRuntimeSetupDialog extends StatefulWidget {
  final TranscriptionConfig? initialConfig;
  final AsrRuntimeSetupDependencies dependencies;

  const AsrRuntimeSetupDialog({
    super.key,
    this.initialConfig,
    required this.dependencies,
  });

  @override
  State<AsrRuntimeSetupDialog> createState() => _AsrRuntimeSetupDialogState();
}

class _AsrRuntimeSetupDialogState extends State<AsrRuntimeSetupDialog> {
  late final AsrRuntimeSetupController _controller;

  @override
  void initState() {
    super.initState();
    final dependencies = widget.dependencies;
    _controller = AsrRuntimeSetupController(
      runtimeManager: dependencies.asrRuntimeManager,
      storagePreflightService: dependencies.asrStoragePreflightService,
      managedStorageService: dependencies.asrManagedStorageService,
      settingsStore: dependencies.transcriptionSettingsStore,
      initialConfig: widget.initialConfig,
    )..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteExistingModelPath() async {
    if (!_controller.canUseExisting) return;
    final path = await showAsrExistingModelPathDialog(context);
    if (path == null || path.trim().isEmpty || !mounted) return;
    await _controller.adoptExistingPath(path);
  }

  Future<void> _browseExistingModel() async {
    if (!_controller.canUseExisting) return;
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: AsrFolderText.pickExistingTitle,
    );
    if (path == null || path.trim().isEmpty || !mounted) return;
    await _controller.adoptExistingPath(path);
  }

  Future<void> _changeManagedStorageLocation() async {
    if (!_controller.canMoveStorage) return;
    final parent = await FilePicker.platform.getDirectoryPath(
      dialogTitle: AsrFolderText.pickNewParentTitle,
    );
    if (parent == null || parent.trim().isEmpty || !mounted) return;
    final result = await _controller.moveStorage(parent);
    if (result == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(AsrSetupText.moved(result))));
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
    await _controller.applyAdvanced(updated);
  }

  VoidCallback? _onAction(AsrSetupAction action) {
    final controller = _controller;
    if (!controller.isEnabled(action)) return null;
    return switch (action) {
      AsrSetupAction.pause => controller.pause,
      AsrSetupAction.later => () => Navigator.pop(context),
      AsrSetupAction.resume => controller.resume,
      AsrSetupAction.advanced => _openAdvanced,
      AsrSetupAction.refresh => controller.refresh,
      AsrSetupAction.install => controller.install,
      AsrSetupAction.start => () => Navigator.pop(context, controller.config),
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _buildDialog(context, _controller),
    );
  }

  Widget _buildDialog(BuildContext context, AsrRuntimeSetupController c) {
    final status = c.status;
    final ready = c.ready;
    final progress = c.installProgress;
    final error = c.error;
    final existingButtons = !c.loading && !c.installing && !c.scanningExisting;

    return PopScope(
      canPop: c.canClose,
      child: AlertDialog(
        titlePadding: EdgeInsets.zero,
        contentPadding: EdgeInsets.zero,
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        title: AsrSetupHeader(ready: ready, installing: c.installing),
        content: SizedBox(
          width: 720,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 650),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AsrSetupStep(
                    number: 1,
                    title: AsrSetupText.chooseStepTitle,
                    subtitle: AsrSetupText.chooseStepSubtitle,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AsrSetupModeField(
                    mode: c.config.mode,
                    onChanged: c.canChangeMode
                        ? (mode) => unawaited(c.changeMode(mode))
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AsrSetupStep(
                    number: 2,
                    title: AsrSetupText.checkStepTitle,
                    subtitle: AsrSetupText.checkStepSubtitle(ready: ready),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (status != null) ...[
                    AsrSetupProfileCard.fromStatus(status),
                    const SizedBox(height: AppSpacing.md),
                    AsrSetupComponentsCard(
                      components: status.components,
                      ready: ready,
                    ),
                  ] else if (c.loading)
                    const AppInlineLoading(
                      message: AsrSetupText.inspecting,
                      framed: true,
                    ),
                  if (c.showsExistingModels) ...[
                    const SizedBox(height: AppSpacing.md),
                    AsrExistingModelCard(
                      scanning: c.scanningExisting,
                      message: c.existingModelMessage,
                      onScan: existingButtons ? c.scanExisting : null,
                      onPastePath: existingButtons
                          ? _pasteExistingModelPath
                          : null,
                      onBrowse: existingButtons ? _browseExistingModel : null,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  AsrStoragePreflightCard(
                    result: c.storage,
                    loading: c.loading,
                    onChangeLocation: c.installing
                        ? null
                        : _changeManagedStorageLocation,
                  ),
                  if (progress != null && c.showsProgress) ...[
                    const SizedBox(height: AppSpacing.lg),
                    AsrInstallProgressCard(
                      progress: progress,
                      paused: c.paused,
                      failed: c.failed,
                      onPause: c.installing ? c.pause : null,
                      onResume: c.paused ? c.resume : null,
                      onRetry: c.failed ? c.retry : null,
                      retryLabel: c.retryLabel,
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    AsrInstallErrorCard(message: error),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  const AsrSetupHint(),
                ],
              ),
            ),
          ),
        ),
        actions: [
          for (final action in c.actions)
            AsrSetupActionButton(
              action: action,
              onPressed: _onAction(action),
              storageBlocked: c.storageBlocked,
            ),
        ],
      ),
    );
  }
}
