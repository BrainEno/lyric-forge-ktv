import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/services/media_import_service.dart';

/// The phone's 导入音频或视频 flow (D-056): choose where from, pick, watch
/// the copy/extraction progress, read what happened.
///
/// Returns null when the user backs out before picking anything.
Future<MediaImportResult?> runMediaImport(
  BuildContext context,
  MediaImportService service,
) async {
  final source = service.supportsPhotoLibrary || service.supportsVideo
      ? await showMediaImportSourceSheet(context, service)
      : MediaImportSource.files;
  if (source == null || !context.mounted) return null;

  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  final progress = ValueNotifier<MediaImportProgress?>(null);
  var dialogOpen = false;
  final MediaImportResult result;
  try {
    result = await service.importMedia(
      source,
      onProgress: (step) {
        progress.value = step;
        // The dialog appears once the picker has closed and work starts.
        if (dialogOpen || !context.mounted) return;
        dialogOpen = true;
        unawaited(
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            useRootNavigator: true,
            builder: (_) => PopScope(
              canPop: false,
              child: MediaImportProgressDialog(progress: progress),
            ),
          ),
        );
      },
    );
  } catch (error) {
    if (dialogOpen) navigator.pop();
    progress.dispose();
    messenger.showSnackBar(
      SnackBar(content: Text('导入失败：$error'), backgroundColor: AppColors.error),
    );
    return null;
  }
  if (dialogOpen) navigator.pop();
  progress.dispose();
  if (result.cancelled) return result;
  if (!context.mounted) return result;

  final failures = result.failures;
  messenger.showSnackBar(
    SnackBar(
      content: Text(mediaImportSummary(result)),
      duration: const Duration(seconds: 6),
      action: failures.isEmpty
          ? null
          : SnackBarAction(
              label: '查看原因',
              onPressed: () {
                if (!context.mounted) return;
                unawaited(showMediaImportFailures(context, failures));
              },
            ),
    ),
  );
  return result;
}

/// One line for the snack bar: what was imported and what was not.
String mediaImportSummary(MediaImportResult result) {
  final count = result.importedPaths.length;
  final failed = result.failures.length;
  final parts = <String>[];
  if (count > 0) {
    parts.add(
      result.extractedFromVideo > 0
          ? '已导入 $count 首歌曲（其中 ${result.extractedFromVideo} 个视频已提取为音频）'
          : '已导入 $count 首歌曲',
    );
  }
  if (failed > 0) {
    parts.add(
      failed == 1 && count == 0
          ? '没有导入：${result.failures.single.reason}'
          : '$failed 个文件没有导入',
    );
  }
  return parts.isEmpty ? '没有选择可以导入的文件' : parts.join('，');
}

/// 从“文件”选择 / 从相册选择视频.
Future<MediaImportSource?> showMediaImportSourceSheet(
  BuildContext context,
  MediaImportService service,
) {
  final showFilesHint = defaultTargetPlatform == TargetPlatform.iOS;
  return showModalBottomSheet<MediaImportSource>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: AppColors.bgSurface,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text('导入歌曲', style: theme.textTheme.titleMedium),
            ),
            ListTile(
              key: const ValueKey('media-import-source-files'),
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('从“文件”选择'),
              subtitle: Text(
                service.supportsVideo
                    ? '音频或视频：MP3、M4A、FLAC、WAV、MP4、MOV 等，可多选'
                    : '音频文件：MP3、M4A、FLAC、WAV 等，可多选',
              ),
              onTap: () =>
                  Navigator.of(sheetContext).pop(MediaImportSource.files),
            ),
            if (service.supportsPhotoLibrary && service.supportsVideo)
              ListTile(
                key: const ValueKey('media-import-source-photos'),
                leading: const Icon(Icons.video_library_rounded),
                title: const Text('从相册选择视频'),
                subtitle: const Text('自动提取声音，保存成较小的音频文件'),
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(MediaImportSource.photoLibrary),
              ),
            if (service.supportsVideo)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  0,
                ),
                child: Text(
                  showFilesHint
                      ? '视频只保留声音，不会占用视频的空间。也可以在系统“文件”App 里把歌曲拷进本 App 的 Imported Audio 文件夹，再到音乐库点“刷新音乐文件夹”。'
                      : '视频只保留声音，不会占用视频的空间。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// The list of files that were not imported, with the reason for each.
Future<void> showMediaImportFailures(
  BuildContext context,
  List<MediaImportFailure> failures,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('这些文件没有导入'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final failure in failures)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(failure.name),
                subtitle: Text(failure.reason),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

class MediaImportProgressDialog extends StatelessWidget {
  final ValueListenable<MediaImportProgress?> progress;

  const MediaImportProgressDialog({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('media-import-progress'),
      content: ValueListenableBuilder<MediaImportProgress?>(
        valueListenable: progress,
        builder: (context, step, _) {
          final label = step == null
              ? '正在准备…'
              : step.phase == MediaImportPhase.extracting
              ? '正在提取视频里的声音（${step.index + 1}/${step.total}）'
              : '正在保存歌曲（${step.index + 1}/${step.total}）';
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox.square(
                    dimension: AppSpacing.lg,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text(label)),
                ],
              ),
              if (step != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  step.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
