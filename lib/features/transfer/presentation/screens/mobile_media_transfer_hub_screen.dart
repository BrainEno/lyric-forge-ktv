import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/services/audio_library_import_service.dart';
import '../../domain/models/media_transfer_batch.dart';
import '../../domain/services/media_hub_client_service.dart';
import '../../domain/services/media_transfer_service.dart';

class MobileMediaTransferHubScreen extends StatefulWidget {
  const MobileMediaTransferHubScreen({super.key});

  @override
  State<MobileMediaTransferHubScreen> createState() =>
      _MobileMediaTransferHubScreenState();
}

class _MobileMediaTransferHubScreenState
    extends State<MobileMediaTransferHubScreen> {
  late final MediaHubClientService _client;
  late final MediaTransferService _transfers;
  late final AudioLibraryImportService _audioImport;

  MediaTransferItemProgress? _activeUpload;
  MediaTransferBatchResult? _lastResult;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final services = ServiceLocatorGlobal.I;
    _client = services.mediaHubClientService;
    _transfers = services.mediaTransferService;
    _audioImport = services.audioLibraryImportService;
  }

  Future<void> _openDesktopLibrary() async {
    await Navigator.pushNamed(context, Routes.remoteBrowse);
    if (mounted) setState(() {});
  }

  Future<void> _sendLocalMusic() async {
    if (_busy) return;
    if (!_client.isConnected) {
      _showMessage('请先连接电脑，再发送本机音乐');
      await _openDesktopLibrary();
      return;
    }

    setState(() {
      _busy = true;
      _activeUpload = null;
      _lastResult = null;
    });

    try {
      final paths = await _audioImport.pickAudioFiles();
      if (paths.isEmpty) return;

      final result = await _transfers.uploadLocalFiles(
        paths,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _activeUpload = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _lastResult = result;
        _activeUpload = null;
      });

      final completed = result.completed.length;
      final failed = result.failed.length;
      _showMessage(
        failed == 0
            ? '已发送 $completed 首音乐到电脑并自动加入电脑音乐库'
            : '已发送 $completed 首，$failed 首失败，可再次选择重试',
        error: completed == 0 && failed > 0,
      );
    } catch (error) {
      _showMessage('发送音乐失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
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
                  onPressed: _busy ? null : _openDesktopLibrary,
                ),
                const SizedBox(height: AppSpacing.md),
                _TransferActionCard(
                  icon: Icons.upload_file_rounded,
                  title: '发送本机音乐到电脑',
                  subtitle: connected
                      ? '可一次多选多首歌曲。电脑完整收到文件后会保存到 LyricForge/Incoming，并自动读取标签、封面并加入 Library。'
                      : '连接电脑后，可以把手机里的本地音乐批量发送到电脑。',
                  actionLabel: connected ? '选择歌曲并发送' : '先连接电脑',
                  onPressed: _busy ? null : _sendLocalMusic,
                ),
                if (_activeUpload != null) ...[
                  SizedBox(height: layout.sectionGap),
                  _UploadProgressCard(progress: _activeUpload!),
                ],
                if (_lastResult != null) ...[
                  SizedBox(height: layout.sectionGap),
                  _TransferResultCard(result: _lastResult!),
                ],
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

class _UploadProgressCard extends StatelessWidget {
  final MediaTransferItemProgress progress;

  const _UploadProgressCard({required this.progress});

  @override
  Widget build(BuildContext context) {
    final status = switch (progress.status) {
      MediaTransferItemStatus.queued => '等待发送',
      MediaTransferItemStatus.transferring => '正在发送',
      MediaTransferItemStatus.completed => '已完成',
      MediaTransferItemStatus.failed => '发送失败',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$status · ${progress.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(value: progress.fraction),
            if (progress.error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                progress.error!,
                style: const TextStyle(color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TransferResultCard extends StatelessWidget {
  final MediaTransferBatchResult result;

  const _TransferResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '发送结果',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('成功 ${result.completed.length} 首 · 失败 ${result.failed.length} 首'),
            if (result.failed.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              for (final item in result.failed.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${item.title}：${item.error ?? '未知错误'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.error,
                        ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
