import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/models/local_media_library_entry.dart';
import '../../../player/domain/repositories/local_media_library_repository.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/media_transfer_batch.dart';
import '../../domain/models/media_transfer_queue.dart';
import '../../domain/services/media_transfer_queue_service.dart';
import 'remote_catalog_utils.dart';

class MobileDownloadManagerScreen extends StatefulWidget {
  const MobileDownloadManagerScreen({super.key});

  @override
  State<MobileDownloadManagerScreen> createState() =>
      _MobileDownloadManagerScreenState();
}

class _MobileDownloadManagerScreenState
    extends State<MobileDownloadManagerScreen> {
  late final LocalMediaLibraryRepository _library;
  late final PlaybackSessionService _session;
  late final MediaTransferQueueService _queue;
  final TextEditingController _searchController = TextEditingController();

  List<LocalMediaLibraryEntry> _downloads = const <LocalMediaLibraryEntry>[];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final services = ServiceLocatorGlobal.I;
    _library = services.localMediaLibraryRepository;
    _session = services.playbackSessionService;
    _queue = services.mediaTransferQueueService;
    _searchController.addListener(_onSearchChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _library.getAll();
      final downloads = entries
          .where(
            (entry) =>
                !entry.isMissing &&
                isManagedRemoteDownloadPath(entry.sourcePath),
          )
          .toList(growable: false)
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
      if (mounted) setState(() => _downloads = downloads);
    } catch (error) {
      if (mounted) setState(() => _error = '读取下载内容失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<LocalMediaLibraryEntry> get _visibleDownloads {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _downloads;
    return _downloads.where((entry) {
      final fileName = _fileName(entry.sourcePath).toLowerCase();
      return fileName.contains(query) ||
          (entry.embeddedTitle?.toLowerCase().contains(query) ?? false) ||
          (entry.embeddedArtist?.toLowerCase().contains(query) ?? false) ||
          (entry.embeddedAlbum?.toLowerCase().contains(query) ?? false);
    }).toList(growable: false);
  }

  String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  String _titleFor(LocalMediaLibraryEntry entry) {
    final embedded = entry.embeddedTitle?.trim();
    if (embedded != null && embedded.isNotEmpty) return embedded;
    final fileName = _fileName(entry.sourcePath);
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  PlaybackItem _itemFor(LocalMediaLibraryEntry entry) {
    final duration = entry.durationMs == null
        ? null
        : Duration(milliseconds: entry.durationMs!);
    return PlaybackItem(
      id: 'local:${entry.sourcePath}',
      title: _titleFor(entry),
      artist: entry.embeddedArtist,
      artworkPath: entry.embeddedArtworkPath,
      audioAsset: AudioAsset(
        originalPath: entry.sourcePath,
        format: entry.format,
        duration: duration,
        thumbnailPath: entry.embeddedArtworkPath,
        metadata: <String, dynamic>{
          'transferSource': 'media-hub',
          if (entry.embeddedAlbum?.trim().isNotEmpty == true)
            'album': entry.embeddedAlbum!.trim(),
        },
      ),
    );
  }

  Future<void> _play(LocalMediaLibraryEntry entry) async {
    final visible = _visibleDownloads;
    final index = visible.indexWhere(
      (candidate) => candidate.sourcePath == entry.sourcePath,
    );
    if (index < 0) return;
    try {
      await _session.setQueue(
        visible.map(_itemFor).toList(growable: false),
        startIndex: index,
      );
    } catch (error) {
      if (mounted) setState(() => _error = '播放失败：$error');
    }
  }

  Future<void> _delete(LocalMediaLibraryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除下载？'),
        content: Text('将从手机中删除“${_titleFor(entry)}”的音频文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final current = _session.currentState.currentItem;
      if (current?.audioAsset.originalPath == entry.sourcePath) {
        await _session.clearQueue(keepCurrent: false);
      }
      final file = File(entry.sourcePath);
      if (await file.exists()) await file.delete();
      await _library.remove(entry.sourcePath);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除本地下载')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '删除失败：$error');
    }
  }

  Future<void> _clearMissing() async {
    await _library.removeMissing();
    await _load();
  }

  int get _totalBytes => _downloads.fold<int>(
        0,
        (total, entry) => total + (entry.sourceSizeBytes ?? 0),
      );

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final visible = _visibleDownloads;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.bgBase,
        title: const Text('下载'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'missing') unawaited(_clearMissing());
              if (value == 'completed') unawaited(_queue.clearCompleted());
            },
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'missing', child: Text('清理失效记录')),
              PopupMenuItem(value: 'completed', child: Text('清理已完成任务')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.all(layout.pageGutter),
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  gradient: AppColors.cardGradient,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                  border: Border.all(color: AppColors.borderMuted),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.bgHighlight,
                      child: Icon(
                        Icons.download_done_rounded,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_downloads.length} 首已下载',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatBytes(_totalBytes),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    if (visible.isNotEmpty)
                      FilledButton.tonalIcon(
                        onPressed: () => _play(visible.first),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('播放'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StreamBuilder<MediaTransferQueueSnapshot>(
                stream: _queue.stateStream,
                initialData: _queue.currentState,
                builder: (context, snapshot) {
                  final state =
                      snapshot.data ?? const MediaTransferQueueSnapshot();
                  final downloads = state.items.where((item) {
                    return item.direction ==
                            MediaTransferDirection.downloadFromDesktop &&
                        item.status != MediaTransferQueueStatus.completed;
                  }).toList(growable: false);
                  if (downloads.isEmpty) return const SizedBox.shrink();
                  return _DownloadTasksCard(
                    items: downloads,
                    queue: _queue,
                    formatBytes: _formatBytes,
                  );
                },
              ),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索已下载歌曲、艺人或专辑',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除',
                          onPressed: _searchController.clear,
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (_loading && _downloads.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    children: [
                      Icon(
                        Icons.download_for_offline_outlined,
                        size: 48,
                        color: AppColors.textTertiary,
                      ),
                      SizedBox(height: AppSpacing.sm),
                      Text(
                        '还没有匹配的已下载歌曲',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                )
              else
                for (final entry in visible) ...[
                  _DownloadedTrackTile(
                    entry: entry,
                    title: _titleFor(entry),
                    formatBytes: _formatBytes,
                    onPlay: () => _play(entry),
                    onDelete: () => _delete(entry),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadTasksCard extends StatelessWidget {
  final List<MediaTransferQueueItem> items;
  final MediaTransferQueueService queue;
  final String Function(int bytes) formatBytes;

  const _DownloadTasksCard({
    required this.items,
    required this.queue,
    required this.formatBytes,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '下载任务',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final item in items) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        item.status == MediaTransferQueueStatus.failed
                            ? item.error ?? '下载失败'
                            : item.totalBytes == null
                                ? item.status.name
                                : '${formatBytes(item.bytesTransferred)} / ${formatBytes(item.totalBytes!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: item.status ==
                                      MediaTransferQueueStatus.failed
                                  ? AppColors.error
                                  : AppColors.textTertiary,
                            ),
                      ),
                    ],
                  ),
                ),
                if (item.status == MediaTransferQueueStatus.failed)
                  IconButton(
                    tooltip: '重试',
                    onPressed: () => queue.retry(item.id),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
              ],
            ),
            if (item.status == MediaTransferQueueStatus.queued ||
                item.status == MediaTransferQueueStatus.transferring)
              LinearProgressIndicator(
                value: item.totalBytes == null || item.totalBytes == 0
                    ? null
                    : (item.bytesTransferred / item.totalBytes!)
                        .clamp(0.0, 1.0)
                        .toDouble(),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _DownloadedTrackTile extends StatelessWidget {
  final LocalMediaLibraryEntry entry;
  final String title;
  final String Function(int bytes) formatBytes;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  const _DownloadedTrackTile({
    required this.entry,
    required this.title,
    required this.formatBytes,
    required this.onPlay,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final artwork = entry.embeddedArtworkPath == null
        ? null
        : File(entry.embeddedArtworkPath!);
    final hasArtwork = artwork != null && artwork.existsSync();
    final subtitle = <String>[
      if (entry.embeddedArtist?.trim().isNotEmpty == true)
        entry.embeddedArtist!.trim(),
      if (entry.embeddedAlbum?.trim().isNotEmpty == true)
        entry.embeddedAlbum!.trim(),
      entry.format.toUpperCase(),
      if (entry.sourceSizeBytes != null) formatBytes(entry.sourceSizeBytes!),
    ].join(' · ');

    return Material(
      color: AppColors.bgElevated,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      child: ListTile(
        onTap: onPlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        ),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          child: Container(
            width: 50,
            height: 50,
            color: AppColors.bgSurface,
            child: hasArtwork
                ? Image.file(artwork!, fit: BoxFit.cover)
                : const Icon(
                    Icons.music_note_rounded,
                    color: AppColors.textSecondary,
                  ),
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'delete') onDelete();
          },
          itemBuilder: (_) => const <PopupMenuEntry<String>>[
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline_rounded),
                  SizedBox(width: AppSpacing.sm),
                  Text('从手机删除'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
