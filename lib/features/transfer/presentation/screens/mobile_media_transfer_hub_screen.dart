import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/services/audio_library_import_service.dart';
import '../../domain/models/media_transfer_batch.dart';
import '../../domain/models/media_transfer_queue.dart';
import '../../domain/services/media_hub_client_service.dart';
import '../../domain/services/media_transfer_queue_service.dart';

class MobileMediaTransferHubScreen extends StatefulWidget {
  const MobileMediaTransferHubScreen({super.key});

  @override
  State<MobileMediaTransferHubScreen> createState() =>
      _MobileMediaTransferHubScreenState();
}

class _MobileMediaTransferHubScreenState
    extends State<MobileMediaTransferHubScreen> {
  late final MediaHubClientService _client;
  late final MediaTransferQueueService _queue;
  late final AudioLibraryImportService _audioImport;

  bool _picking = false;

  @override
  void initState() {
    super.initState();
    final services = ServiceLocatorGlobal.I;
    _client = services.mediaHubClientService;
    _queue = services.mediaTransferQueueService;
    _audioImport = services.audioLibraryImportService;
    if (_client.isConnected) unawaited(_queue.resume());
  }

  Future<void> _openDesktopLibrary() async {
    await Navigator.pushNamed(context, Routes.remoteBrowse);
    if (!mounted) return;
    if (_client.isConnected) await _queue.resume();
    if (mounted) setState(() {});
  }

  Future<void> _sendLocalMusic() async {
    if (_picking) return;
    if (!_client.isConnected) {
      _showMessage('请先连接电脑，再发送本机音乐');
      await _openDesktopLibrary();
      return;
    }

    setState(() => _picking = true);
    try {
      final paths = await _audioImport.pickAudioFiles();
      if (paths.isEmpty) return;
      await _queue.enqueueUploads(paths);
      await _queue.resume();
      _showMessage('已加入 ${paths.length} 首到后台传输队列');
    } catch (error) {
      _showMessage('加入传输队列失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : AppColors.bgSurface,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final connected = _client.isConnected;
    final connection = _client.currentConnection;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text('跨设备传输'),
        backgroundColor: AppColors.bgBase,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: layout.contentMaxWidth),
            child: ListView(
              padding: EdgeInsets.all(layout.pageGutter),
              children: [
                _ConnectionCard(
                  connected: connected,
                  host: connection?.host,
                  onConnect: _openDesktopLibrary,
                ),
                SizedBox(height: layout.sectionGap),
                _TransferActionCard(
                  icon: Icons.computer_rounded,
                  title: '浏览电脑音乐',
                  subtitle: '直接流式播放电脑里的歌曲，或多选后批量下载到手机并自动加入本地音乐库。',
                  actionLabel: connected ? '打开电脑音乐库' : '连接电脑',
                  onPressed: _picking ? null : _openDesktopLibrary,
                ),
                const SizedBox(height: AppSpacing.md),
                _TransferActionCard(
                  icon: Icons.upload_file_rounded,
                  title: '发送本机音乐到电脑',
                  subtitle: connected
                      ? '可一次多选多首歌曲。任务会进入持久化后台队列，电脑完整收到后自动读取标签、封面并加入 Library。'
                      : '连接电脑后，可以把手机里的本地音乐批量发送到电脑。',
                  actionLabel: connected
                      ? (_picking ? '正在选择...' : '选择歌曲并加入队列')
                      : '先连接电脑',
                  onPressed: _picking ? null : _sendLocalMusic,
                ),
                SizedBox(height: layout.sectionGap),
                StreamBuilder<MediaTransferQueueSnapshot>(
                  stream: _queue.stateStream,
                  initialData: _queue.currentState,
                  builder: (context, snapshot) {
                    return _PersistentTransferQueueCard(
                      snapshot: snapshot.data ?? const MediaTransferQueueSnapshot(),
                      queue: _queue,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final bool connected;
  final String? host;
  final VoidCallback onConnect;

  const _ConnectionCard({
    required this.connected,
    required this.host,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Icon(
              connected ? Icons.link_rounded : Icons.link_off_rounded,
              size: 30,
              color: connected ? AppColors.success : AppColors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connected ? '已连接电脑' : '尚未连接电脑',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    connected && host != null
                        ? host!
                        : '扫描电脑端“跨设备传输中心”的二维码即可连接。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            if (!connected)
              TextButton(
                onPressed: onConnect,
                child: const Text('连接'),
              ),
          ],
        ),
      ),
    );
  }
}

class _TransferActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onPressed;

  const _TransferActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    return Card(
      child: Padding(
        padding: EdgeInsets.all(layout.isCompact ? AppSpacing.md : AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                  ),
                  child: Icon(icon, color: AppColors.accent),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(actionLabel),
              style: FilledButton.styleFrom(
                minimumSize: Size(0, layout.minimumInteractiveExtent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersistentTransferQueueCard extends StatelessWidget {
  final MediaTransferQueueSnapshot snapshot;
  final MediaTransferQueueService queue;

  const _PersistentTransferQueueCard({
    required this.snapshot,
    required this.queue,
  });

  @override
  Widget build(BuildContext context) {
    final active = snapshot.active;
    final recent = snapshot.items.reversed.take(6).toList(growable: false);
    final pending = snapshot.queued.length;
    final failed = snapshot.failed.length;
    final completed = snapshot.completed.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sync_alt_rounded, color: AppColors.accent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '传输队列',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                if (snapshot.isPaused)
                  const Chip(label: Text('已暂停'))
                else if (snapshot.isProcessing)
                  const Chip(label: Text('传输中')),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '等待 $pending · 失败 $failed · 已完成 $completed',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            if (snapshot.pauseReason != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                snapshot.pauseReason!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
            ],
            if (active != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                '正在传输 · ${active.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              LinearProgressIndicator(value: _fraction(active)),
            ],
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (snapshot.isPaused)
                  FilledButton.icon(
                    onPressed: queue.resume,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('继续'),
                  )
                else if (snapshot.isProcessing || pending > 0)
                  OutlinedButton.icon(
                    onPressed: () => queue.pause(),
                    icon: const Icon(Icons.pause_rounded),
                    label: const Text('暂停'),
                  ),
                if (failed > 0)
                  OutlinedButton.icon(
                    onPressed: queue.retryFailed,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('重试失败项'),
                  ),
                if (completed > 0)
                  TextButton.icon(
                    onPressed: queue.clearCompleted,
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: const Text('清理已完成'),
                  ),
              ],
            ),
            if (recent.isNotEmpty) ...[
              const Divider(height: AppSpacing.lg),
              for (final item in recent) _QueueItemRow(item: item, queue: queue),
            ] else ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                '还没有传输任务。选择本机音乐后会从这里进入后台队列。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  double? _fraction(MediaTransferQueueItem item) {
    final total = item.totalBytes;
    if (total == null || total <= 0) return null;
    return (item.bytesTransferred / total).clamp(0.0, 1.0).toDouble();
  }
}

class _QueueItemRow extends StatelessWidget {
  final MediaTransferQueueItem item;
  final MediaTransferQueueService queue;

  const _QueueItemRow({required this.item, required this.queue});

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (item.status) {
      MediaTransferQueueStatus.queued =>
        (Icons.schedule_rounded, '等待', AppColors.textSecondary),
      MediaTransferQueueStatus.transferring =>
        (Icons.sync_rounded, '传输中', AppColors.accent),
      MediaTransferQueueStatus.completed =>
        (Icons.check_circle_rounded, '完成', AppColors.success),
      MediaTransferQueueStatus.failed =>
        (Icons.error_rounded, '失败', AppColors.error),
    };
    final direction = item.direction == MediaTransferDirection.uploadToDesktop
        ? '发送到电脑'
        : '下载到本机';

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        item.error == null ? '$direction · $label' : '$direction · ${item.error}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: item.status == MediaTransferQueueStatus.failed
          ? IconButton(
              tooltip: '重试',
              onPressed: () => queue.retry(item.id),
              icon: const Icon(Icons.refresh_rounded),
            )
          : item.status == MediaTransferQueueStatus.completed
              ? IconButton(
                  tooltip: '从队列移除',
                  onPressed: () => queue.remove(item.id),
                  icon: const Icon(Icons.close_rounded),
                )
              : null,
    );
  }
}
