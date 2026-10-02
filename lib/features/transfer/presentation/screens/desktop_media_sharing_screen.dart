import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/media_hub_session.dart';
import '../../domain/models/shared_audio_track.dart';
import '../../domain/services/media_hub_service.dart';

class DesktopMediaSharingScreen extends StatefulWidget {
  const DesktopMediaSharingScreen({super.key});

  @override
  State<DesktopMediaSharingScreen> createState() =>
      _DesktopMediaSharingScreenState();
}

class _DesktopMediaSharingScreenState extends State<DesktopMediaSharingScreen> {
  static const _uuid = Uuid();

  late final MediaHubService _mediaHubService;
  late final ProjectRepository _projectRepository;
  late MediaHubState _hubState;
  StreamSubscription<MediaHubState>? _stateSubscription;

  final List<SharedAudioTrack> _tracks = [];
  bool _busy = false;

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    _mediaHubService = ServiceLocatorGlobal.I.mediaHubService;
    _projectRepository = ServiceLocatorGlobal.I.projectRepository;
    _hubState = _mediaHubService.currentState;
    _stateSubscription = _mediaHubService.stateStream.listen((state) {
      if (mounted) setState(() => _hubState = state);
    });
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _pickAudioFiles() async {
    if (_hubState.isRunning || _busy) return;

    try {
      const supportedExtensions = [
        'mp3',
        'flac',
        'wav',
        'm4a',
        'mp4',
        'ogg',
        'aac',
      ];
      final useUnfilteredMacPicker = Platform.isMacOS;
      final result = await FilePicker.platform.pickFiles(
        type: useUnfilteredMacPicker ? FileType.any : FileType.custom,
        allowedExtensions:
            useUnfilteredMacPicker ? null : supportedExtensions,
        allowMultiple: true,
        dialogTitle: '选择要共享的音频文件',
        allowCompression: false,
        withData: false,
        withReadStream: false,
      );
      if (result == null || result.files.isEmpty) return;

      final selected = <SharedAudioTrack>[];
      for (final picked in result.files) {
        final path = picked.path;
        if (path == null) continue;

        final file = File(path);
        if (!await file.exists()) continue;

        final fileName =
            file.uri.pathSegments.isEmpty ? path : file.uri.pathSegments.last;
        final extension = _extensionOf(fileName);
        if (!_isSupportedFormat(extension)) continue;

        selected.add(
          SharedAudioTrack(
            id: _uuid.v4(),
            title: _titleOf(fileName),
            localPath: path,
            format: extension,
            byteLength: await file.length(),
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        final existingPaths = _tracks.map((track) => track.localPath).toSet();
        _tracks.addAll(
          selected.where((track) => !existingPaths.contains(track.localPath)),
        );
      });

      if (selected.isEmpty) {
        _showMessage('没有找到可共享的受支持音频文件');
      }
    } catch (error) {
      _showMessage('选择音频失败：$error', error: true);
    }
  }

  Future<void> _addProject() async {
    if (_hubState.isRunning || _busy) return;

    setState(() => _busy = true);
    try {
      final projects = (await _projectRepository.getAllProjects())
          .where((project) => project.audioAsset != null)
          .toList();

      if (!mounted) return;
      if (projects.isEmpty) {
        _showMessage('当前没有可共享音频的工程');
        return;
      }

      final selected = await showDialog<ProjectManifest>(
        context: context,
        builder: (context) {
          return SimpleDialog(
            title: const Text('选择要共享的工程'),
            children: projects.map((project) {
              final hasLyrics = project.hasLyrics;
              return SimpleDialogOption(
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
                      if (project.artist != null && project.artist!.isNotEmpty)
                        project.artist!,
                      if (hasLyrics) '包含歌词',
                    ].join(' · '),
                  ),
                ),
              );
            }).toList(),
          );
        },
      );

      if (selected == null || !mounted) return;
      final asset = selected.audioAsset!;
      final path = asset.originalPath;
      final sourceFile = File(path);
      if (!await sourceFile.exists()) {
        _showMessage('工程原声音频文件不存在', error: true);
        return;
      }

      final track = SharedAudioTrack(
        id: 'project-' + selected.id,
        title: selected.name,
        artist: selected.artist,
        album: selected.album,
        localPath: path,
        format: asset.format,
        byteLength: await sourceFile.length(),
        duration: asset.duration,
        lyrics: selected.lyricDocument,
      );

      if (!mounted) return;
      setState(() {
        _tracks.removeWhere((item) => item.id == track.id);
        _tracks.add(track);
      });
      _showMessage(selected.hasLyrics
          ? '已加入工程音频和歌词'
          : '已加入工程音频');
    } catch (error) {
      _showMessage('读取工程失败：' + error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startSharing() async {
    if (_tracks.isEmpty || _busy || _hubState.isRunning) return;

    setState(() => _busy = true);
    try {
      await _mediaHubService.startSharing(_tracks);
    } catch (error) {
      _showMessage('启动共享失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopSharing() async {
    if (_busy || !_hubState.isRunning) return;

    setState(() => _busy = true);
    try {
      await _mediaHubService.stopSharing();
    } catch (error) {
      _showMessage('停止共享失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyPairingUri(MediaHubSession session) async {
    await Clipboard.setData(
      ClipboardData(text: session.pairingUri.toString()),
    );
    _showMessage('配对信息已复制');
  }

  void _removeTrack(String id) {
    if (_hubState.isRunning) return;
    setState(() => _tracks.removeWhere((track) => track.id == id));
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

  String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  String _titleOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  bool _isSupportedFormat(String extension) {
    return const {'mp3', 'flac', 'wav', 'm4a', 'mp4', 'ogg', 'aac'}
        .contains(extension);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return bytes.toString() + ' B';
    if (bytes < 1024 * 1024) {
      return (bytes / 1024).toStringAsFixed(1) + ' KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return (bytes / (1024 * 1024)).toStringAsFixed(1) + ' MB';
    }
    return (bytes / (1024 * 1024 * 1024)).toStringAsFixed(2) + ' GB';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) {
      return const Scaffold(
        backgroundColor: AppColors.bgBase,
        body: Center(child: Text('音乐共享服务请在桌面端启动')),
      );
    }

    final session = _hubState.session;
    final running = _hubState.isRunning;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text('远程音乐库'),
        backgroundColor: AppColors.bgBase,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _statusCard(session),
                const SizedBox(height: AppSpacing.md),
                _libraryCard(running),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: running || _busy ? null : _pickAudioFiles,
                      icon: const Icon(Icons.audio_file_outlined),
                      label: const Text('添加音频'),
                    ),
                    OutlinedButton.icon(
                      onPressed: running || _busy ? null : _addProject,
                      icon: const Icon(Icons.library_music_outlined),
                      label: const Text('添加工程'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _busy
                          ? null
                          : running
                              ? _stopSharing
                              : _tracks.isEmpty
                                  ? null
                                  : _startSharing,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.pureWhite,
                              ),
                            )
                          : Icon(running ? Icons.stop : Icons.wifi_tethering),
                      label: Text(running ? '停止共享' : '开始共享'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusCard(MediaHubSession? session) {
    final running = _hubState.isRunning;
    final remoteAvailable = session?.remoteAccessAvailable ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  running ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                  color: running ? AppColors.success : AppColors.textTertiary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    running ? '音乐共享已开启' : '音乐共享未开启',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (running)
                  Chip(
                    avatar: Icon(
                      remoteAvailable ? Icons.public : Icons.lan_outlined,
                      size: 16,
                    ),
                    label: Text(
                      remoteAvailable ? 'Tailscale 远程可用' : '仅局域网',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              running
                  ? '手机端可通过下面的连接信息访问当前共享音乐。'
                  : '选择音频后启动共享；连接 Tailscale 后可跨公网访问。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (session != null) ...[
              const SizedBox(height: AppSpacing.lg),
              ...session.endpoints.map(_endpointRow),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.pureWhite,
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusMedium),
                  ),
                  child: QrImageView(
                    data: session.pairingUri.toString(),
                    size: 184,
                    backgroundColor: AppColors.pureWhite,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('配对信息', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusMedium),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        session.pairingUri.toString(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: '复制配对信息',
                      onPressed: () => _copyPairingUri(session),
                      icon: const Icon(Icons.copy_outlined),
                    ),
                  ],
                ),
              ),
            ],
            if (_hubState.status == MediaHubStatus.failed &&
                _hubState.error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _hubState.error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.error,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _endpointRow(MediaHubEndpoint endpoint) {
    final label = switch (endpoint.kind) {
      MediaHubEndpointKind.tailscale => 'Tailscale',
      MediaHubEndpointKind.lan => '局域网',
      MediaHubEndpointKind.other => '其他',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: SelectableText(
              endpoint.host + ':' + endpoint.port.toString(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _libraryCard(bool running) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('共享音乐', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                Text(
                  _tracks.length.toString() + ' 首',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (_tracks.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.xxl,
                  horizontal: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusMedium),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.audio_file_outlined,
                      size: 40,
                      color: AppColors.textTertiary,
                    ),
                    SizedBox(height: AppSpacing.sm),
                    Text('还没有选择共享音频'),
                  ],
                ),
              )
            else
              ..._tracks.map(
                (track) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.music_note_outlined),
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    track.format.toUpperCase() +
                        ' · ' +
                        _formatBytes(track.byteLength),
                  ),
                  trailing: running
                      ? null
                      : IconButton(
                          tooltip: '移除',
                          onPressed: () => _removeTrack(track.id),
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
