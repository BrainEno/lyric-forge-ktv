import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/services/audio_library_import_service.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/media_hub_session.dart';
import '../../domain/models/shared_audio_track.dart';
import '../../domain/services/media_hub_service.dart';

class DesktopMediaTransferHubScreen extends StatefulWidget {
  const DesktopMediaTransferHubScreen({super.key});

  @override
  State<DesktopMediaTransferHubScreen> createState() =>
      _DesktopMediaTransferHubScreenState();
}

class _DesktopMediaTransferHubScreenState
    extends State<DesktopMediaTransferHubScreen> {
  static const _uuid = Uuid();

  late final MediaHubService _hub;
  late final ProjectRepository _projects;
  late final AudioLibraryImportService _audioImport;
  late MediaHubState _hubState;
  StreamSubscription<MediaHubState>? _subscription;

  final List<SharedAudioTrack> _sharedTracks = [];
  bool _busy = false;

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    final services = ServiceLocatorGlobal.I;
    _hub = services.mediaHubService;
    _projects = services.projectRepository;
    _audioImport = services.audioLibraryImportService;
    _hubState = _hub.currentState;
    _subscription = _hub.stateStream.listen((state) {
      if (mounted) setState(() => _hubState = state);
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _pickAudioFiles() async {
    if (_hubState.isRunning || _busy) return;
    setState(() => _busy = true);
    try {
      final paths = await _audioImport.pickAudioFiles();
      final existing = _sharedTracks.map((track) => track.localPath).toSet();
      final added = <SharedAudioTrack>[];
      for (final path in paths) {
        if (!existing.add(path)) continue;
        final file = File(path);
        if (!await file.exists()) continue;
        final fileName = file.uri.pathSegments.isEmpty ? path : file.uri.pathSegments.last;
        added.add(
          SharedAudioTrack(
            id: _uuid.v4(),
            title: _titleOf(fileName),
            localPath: path,
            format: _extensionOf(fileName),
            byteLength: await file.length(),
          ),
        );
      }
      if (mounted) setState(() => _sharedTracks.addAll(added));
    } catch (error) {
      _showMessage('选择音频失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addProject() async {
    if (_hubState.isRunning || _busy) return;
    setState(() => _busy = true);
    try {
      final projects = (await _projects.getAllProjects())
          .where((project) => project.audioAsset != null)
          .toList(growable: false);
      if (!mounted) return;
      if (projects.isEmpty) {
        _showMessage('当前没有包含音频的工程');
        return;
      }

      final selected = await showDialog<ProjectManifest>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择要共享的工程'),
          children: [
            for (final project in projects)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, project),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.library_music_outlined),
                  title: Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      if (project.artist?.isNotEmpty == true) project.artist!,
                      if (project.hasLyrics) '包含歌词',
                    ].join(' · '),
                  ),
                ),
              ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      final asset = selected.audioAsset!;
      final file = File(asset.originalPath);
      if (!await file.exists()) {
        _showMessage('工程原声音频不存在', error: true);
        return;
      }
      final track = SharedAudioTrack(
        id: 'project-${selected.id}',
        title: selected.name,
        artist: selected.artist,
        album: selected.album,
        localPath: asset.originalPath,
        format: asset.format,
        byteLength: await file.length(),
        duration: asset.duration,
        lyrics: selected.lyricDocument,
      );
      setState(() {
        _sharedTracks.removeWhere((item) => item.id == track.id);
        _sharedTracks.add(track);
      });
    } catch (error) {
      _showMessage('读取工程失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (_busy || _hubState.isRunning) return;
    setState(() => _busy = true);
    try {
      await _hub.startSharing(_sharedTracks);
    } catch (error) {
      _showMessage('启动跨设备传输失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (_busy || !_hubState.isRunning) return;
    setState(() => _busy = true);
    try {
      await _hub.stopSharing();
    } catch (error) {
      _showMessage('停止传输服务失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyPairing(MediaHubSession session) async {
    await Clipboard.setData(ClipboardData(text: session.pairingUri.toString()));
    _showMessage('配对信息已复制');
  }

  void _removeTrack(String id) {
    if (_hubState.isRunning) return;
    setState(() => _sharedTracks.removeWhere((track) => track.id == id));
  }

  String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  String _titleOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
    if (!_isDesktop) {
      return const Scaffold(
        backgroundColor: AppColors.bgBase,
        body: Center(child: Text('跨设备接收服务请在桌面端启动')),
      );
    }

    final layout = AppResponsive.of(context);
    final session = _hubState.session;
    final running = _hubState.isRunning;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text('跨设备传输中心'),
        backgroundColor: AppColors.bgBase,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: layout.contentMaxWidth),
            child: ListView(
              padding: EdgeInsets.all(layout.pageGutter),
              children: [
                _StatusCard(
                  running: running,
                  busy: _busy,
                  sharedCount: _sharedTracks.length,
                  session: session,
                  onStart: _start,
                  onStop: _stop,
                  onCopyPairing: session == null ? null : () => _copyPairing(session),
                ),
                const SizedBox(height: AppSpacing.md),
                if (session != null) ...[
                  _PairingCard(session: session),
                  const SizedBox(height: AppSpacing.md),
                ],
                _IncomingCard(running: running),
                const SizedBox(height: AppSpacing.md),
                _SharedLibraryCard(
                  tracks: _sharedTracks,
                  running: running,
                  busy: _busy,
                  onPickAudio: _pickAudioFiles,
                  onAddProject: _addProject,
                  onRemove: _removeTrack,
                  formatBytes: _formatBytes,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool running;
  final bool busy;
  final int sharedCount;
  final MediaHubSession? session;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback? onCopyPairing;

  const _StatusCard({
    required this.running,
    required this.busy,
    required this.sharedCount,
    required this.session,
    required this.onStart,
    required this.onStop,
    required this.onCopyPairing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  running ? Icons.sync_alt_rounded : Icons.devices_rounded,
                  color: running ? AppColors.success : AppColors.accent,
                  size: 30,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        running ? '跨设备传输已开启' : '电脑 ↔ 手机双向传送',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        running
                            ? '手机可以下载电脑共享音乐，也可以把本地歌曲传回这台电脑。'
                            : '即使不共享任何歌曲，也可以启动纯接收模式，让手机向电脑批量发送音乐。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : running ? onStop : onStart,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded),
                  label: Text(running ? '停止传输服务' : '启动传输服务'),
                ),
                if (running && onCopyPairing != null)
                  OutlinedButton.icon(
                    onPressed: onCopyPairing,
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('复制配对信息'),
                  ),
                Chip(label: Text('共享 $sharedCount 首')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PairingCard extends StatelessWidget {
  final MediaHubSession session;

  const _PairingCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final qr = Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.pureWhite,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: QrImageView(
        data: session.pairingUri.toString(),
        size: layout.isCompact ? 160 : 184,
        backgroundColor: AppColors.pureWhite,
      ),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('扫描二维码连接', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        SelectableText(session.pairingUri.toString()),
        const SizedBox(height: AppSpacing.md),
        for (final endpoint in session.endpoints)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${endpoint.kind.name}: ${endpoint.host}:${endpoint.port}'),
          ),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: layout.isCompactOrMedium
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [qr, const SizedBox(height: AppSpacing.md), details],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [qr, const SizedBox(width: AppSpacing.lg), Expanded(child: details)],
              ),
      ),
    );
  }
}

class _IncomingCard extends StatelessWidget {
  final bool running;

  const _IncomingCard({required this.running});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.move_to_inbox_rounded,
          color: running ? AppColors.success : AppColors.textTertiary,
        ),
        title: const Text('手机 → 电脑接收'),
        subtitle: Text(
          running
              ? '已准备接收。文件完整传完后保存到 LyricForge/Incoming，并自动加入电脑本地音乐库。'
              : '启动传输服务后即可接收手机批量上传。不会把半截文件导入音乐库。',
        ),
      ),
    );
  }
}

class _SharedLibraryCard extends StatelessWidget {
  final List<SharedAudioTrack> tracks;
  final bool running;
  final bool busy;
  final VoidCallback onPickAudio;
  final VoidCallback onAddProject;
  final ValueChanged<String> onRemove;
  final String Function(int bytes) formatBytes;

  const _SharedLibraryCard({
    required this.tracks,
    required this.running,
    required this.busy,
    required this.onPickAudio,
    required this.onAddProject,
    required this.onRemove,
    required this.formatBytes,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('电脑 → 手机共享', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              running
                  ? '服务运行时共享列表锁定；手机可以在线播放或批量下载这些歌曲。'
                  : '可选。即使这里为空，也可以启动纯接收模式。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: running || busy ? null : onPickAudio,
                  icon: const Icon(Icons.audio_file_rounded),
                  label: const Text('添加本地音乐'),
                ),
                OutlinedButton.icon(
                  onPressed: running || busy ? null : onAddProject,
                  icon: const Icon(Icons.library_music_rounded),
                  label: const Text('添加工程'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (tracks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text('没有共享歌曲；当前可作为纯接收服务器使用。'),
              )
            else
              for (final track in tracks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.music_note_rounded),
                  title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [
                      track.format.toUpperCase(),
                      formatBytes(track.byteLength),
                      if (track.hasLyrics) '含歌词',
                    ].join(' · '),
                  ),
                  trailing: IconButton(
                    tooltip: '移除共享',
                    onPressed: running ? null : () => onRemove(track.id),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
