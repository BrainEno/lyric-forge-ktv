import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../domain/models/ktv_recording_session.dart';
import '../../domain/services/audio_preview_service.dart';
import '../../domain/services/ktv_recording_service.dart';
import '../../domain/services/ktv_take_history_store.dart';
import '../recording_time_format.dart';
import 'ktv_take_result_sheet.dart';

/// The project's completed takes: audition, rename, favourite, delete.
///
/// This is the sheet the deleted `_FullScreenKtvView` owned. Its one rule that
/// must not be lost is the mutation lock: while a take is being recorded or a
/// mix is being exported, the same directory is being written, so deleting,
/// renaming or favouriting another take is refused with an explanation instead
/// of being queued behind an ffmpeg run. The guard sits in this widget (not on
/// the caller) so a widget test can put the recording service in `isExporting`
/// and see the refusal.
class KtvTakeHistorySheet extends StatefulWidget {
  /// Shown when the take directory is busy. Public so the screen that opens
  /// this sheet refuses with exactly the same sentence.
  static const lockedExportMessage = '混音正在导出，完成前不能删除、重命名或收藏录音';
  static const lockedRecordingMessage = '录音进行中，停止录音后再管理演唱历史';

  final ProjectManifest project;
  final KtvTakeHistoryStore takeHistoryStore;
  final KtvRecordingService recordingService;
  final AudioPreviewService previewService;

  const KtvTakeHistorySheet({
    super.key,
    required this.project,
    required this.takeHistoryStore,
    required this.recordingService,
    required this.previewService,
  });

  @override
  State<KtvTakeHistorySheet> createState() => _KtvTakeHistorySheetState();
}

class _KtvTakeHistorySheetState extends State<KtvTakeHistorySheet> {
  KtvTakeHistoryScanResult? _scan;
  Object? _error;
  bool _loading = true;
  StreamSubscription<KtvRecordingState>? _recordingSubscription;

  @override
  void initState() {
    super.initState();
    // The sheet stays open while an export finishes elsewhere; re-enable the
    // actions as soon as the service releases the directory.
    _recordingSubscription = widget.recordingService.stateStream.listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _recordingSubscription?.cancel();
    super.dispose();
  }

  KtvRecordingState get _recordingState => widget.recordingService.currentState;

  bool get _mutationLocked {
    final state = _recordingState;
    return state.isRecording || state.isExporting;
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final scan = await widget.takeHistoryStore.scanProject(widget.project);
      if (!mounted) return;
      setState(() {
        _scan = scan;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// Returns false and explains why when the take directory is busy.
  bool _ensureUnlocked() {
    if (!_mutationLocked) return true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          _recordingState.isExporting
              ? KtvTakeHistorySheet.lockedExportMessage
              : KtvTakeHistorySheet.lockedRecordingMessage,
        ),
      ),
    );
    return false;
  }

  Future<void> _toggleFavorite(KtvRecordingSession take) async {
    if (!_ensureUnlocked()) return;
    try {
      await widget.takeHistoryStore.updateProjectTakeMetadata(
        widget.project,
        take,
        isFavorite: !take.isFavorite,
      );
      if (!mounted) return;
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新收藏状态失败：$error')));
    }
  }

  Future<void> _rename(KtvRecordingSession take) async {
    if (!_ensureUnlocked()) return;
    final controller = TextEditingController(text: take.displayName ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('给这次演唱命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: KtvTakeHistoryStore.maxDisplayNameLength,
          decoration: const InputDecoration(
            labelText: '录音名称',
            hintText: '例如：第二遍 / 高音最好的一次',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    // The dialog can stay open long enough for an export to start.
    if (!_ensureUnlocked()) return;
    try {
      await widget.takeHistoryStore.updateProjectTakeMetadata(
        widget.project,
        take,
        displayName: value,
        clearDisplayName: value.trim().isEmpty,
      );
      if (!mounted) return;
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('重命名失败：$error')));
    }
  }

  Future<void> _confirmDelete(KtvRecordingSession take) async {
    if (!_ensureUnlocked()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('永久删除这次演唱录音？'),
        content: const Text('将删除本次录音的人声、混音和记录文件，无法撤销。其他录音不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!_ensureUnlocked()) return;
    try {
      await widget.takeHistoryStore.deleteProjectTake(widget.project, take);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('演唱录音已删除')));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
  }

  Future<void> _openTake(KtvRecordingSession take) async {
    if (!_ensureUnlocked()) return;
    // Close the list first: the result sheet is the same one the record button
    // opens, and stacking two sheets would leave two players on screen.
    final navigator = Navigator.of(context);
    navigator.pop();
    await showModalBottomSheet<void>(
      context: navigator.context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.bgElevated,
      builder: (context) => KtvTakeResultSheet(
        initialSession: take,
        recordingService: widget.recordingService,
        previewService: widget.previewService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scan = _scan;
    final locked = _mutationLocked;
    final takes = scan?.takes ?? const <KtvRecordingSession>[];
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Text(
          '演唱历史（${takes.length}）',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (locked) ...[
          const SizedBox(height: AppSpacing.sm),
          _HistoryNotice(
            icon: Icons.lock_clock_rounded,
            color: AppColors.warning,
            message: _recordingState.isExporting
                ? KtvTakeHistorySheet.lockedExportMessage
                : KtvTakeHistorySheet.lockedRecordingMessage,
          ),
        ],
        if (scan != null && scan.recoveredCount > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          _HistoryNotice(
            icon: Icons.restore_rounded,
            color: AppColors.info,
            message: '已恢复 ${scan.recoveredCount} 次中断录音，原始人声已保留；自动混音已停用',
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          _HistoryNotice(
            icon: Icons.error_outline_rounded,
            color: AppColors.error,
            message: '读取演唱历史失败：$_error',
          )
        else if (takes.isEmpty)
          const ListTile(title: Text('暂无已完成的演唱录音')),
        for (final take in takes)
          Builder(
            builder: (tileContext) {
              final timestamp = take.startedAt
                  .toLocal()
                  .toString()
                  .split('.')
                  .first;
              final customName = take.displayName?.trim();
              final hasCustomName = customName?.isNotEmpty == true;
              return ListTile(
                leading: Icon(
                  take.isFavorite
                      ? Icons.star_rounded
                      : Icons.library_music_outlined,
                  color: take.isFavorite ? AppColors.accent : null,
                ),
                title: Text(hasCustomName ? customName! : timestamp),
                subtitle: Text(
                  '${hasCustomName ? "$timestamp · " : ""}'
                  '${formatRecordingTime(take.duration)} · '
                  '${take.alignmentReliable ? "可重新混音" : "时间轴异常，仅保留原始人声"}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: take.isFavorite ? '取消收藏' : '收藏并置顶',
                      onPressed: locked
                          ? null
                          : () => unawaited(_toggleFavorite(take)),
                      icon: Icon(
                        take.isFavorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '更多操作',
                      enabled: !locked,
                      onSelected: (action) {
                        if (action == 'rename') {
                          unawaited(_rename(take));
                        } else if (action == 'delete') {
                          unawaited(_confirmDelete(take));
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'rename', child: Text('重命名')),
                        PopupMenuItem(value: 'delete', child: Text('永久删除')),
                      ],
                    ),
                  ],
                ),
                onTap: () => unawaited(_openTake(take)),
              );
            },
          ),
      ],
    );
  }
}

class _HistoryNotice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;

  const _HistoryNotice({
    required this.icon,
    required this.color,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
