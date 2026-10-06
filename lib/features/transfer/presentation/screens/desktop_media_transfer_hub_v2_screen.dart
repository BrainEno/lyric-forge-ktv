import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../data/services/local_library_media_share_catalog.dart';
import '../../domain/models/media_hub_session.dart';
import '../../domain/models/shared_audio_track.dart';
import '../../domain/services/media_hub_service.dart';

/// Desktop-first transfer center that makes pairing a one-step operation.
///
/// Opening this screen automatically exposes the existing desktop Library to
/// the phone and starts the Media Hub if needed, so the QR code is immediately
/// visible instead of requiring a separate "start service" step first.
class DesktopMediaTransferHubV2Screen extends StatefulWidget {
  const DesktopMediaTransferHubV2Screen({super.key});

  @override
  State<DesktopMediaTransferHubV2Screen> createState() =>
      _DesktopMediaTransferHubV2ScreenState();
}

class _DesktopMediaTransferHubV2ScreenState
    extends State<DesktopMediaTransferHubV2Screen> {
  late final MediaHubService _hub;
  late final LocalLibraryMediaShareCatalog _catalog;
  late MediaHubState _hubState;
  StreamSubscription<MediaHubState>? _hubSubscription;

  List<SharedAudioTrack> _tracks = const [];
  bool _busy = false;
  bool _initializing = true;
  String? _error;

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
    _catalog = LocalLibraryMediaShareCatalog(
      libraryRepository: services.localMediaLibraryRepository,
    );
    _hubState = _hub.currentState;
    _hubSubscription = _hub.stateStream.listen((state) {
      if (mounted) setState(() => _hubState = state);
    });
    unawaited(_prepare());
  }

  @override
  void dispose() {
    unawaited(_hubSubscription?.cancel());
    // Keep the service alive after leaving this screen. A paired phone may be
    // transferring while the desktop user is browsing or playing music.
    super.dispose();
  }

  Future<void> _prepare() async {
    if (!_isDesktop) {
      if (mounted) setState(() => _initializing = false);
      return;
    }

    try {
      final tracks = await _catalog.build();
      if (!mounted) return;
      setState(() => _tracks = tracks);

      final session = _hub.currentSession;
      final needsRestart = !_hub.isRunning || session?.trackCount != tracks.length;
      if (needsRestart) {
        await _hub.startSharing(tracks);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '启动跨设备传输失败：$error');
      }
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<void> _refreshAndRestart() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final tracks = await _catalog.build();
      await _hub.startSharing(tracks);
      if (!mounted) return;
      setState(() => _tracks = tracks);
      _showMessage('电脑音乐库已刷新；二维码已更新，请让手机重新扫码。');
    } catch (error) {
      if (mounted) setState(() => _error = '刷新共享音乐库失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (_busy || _hub.isRunning) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final tracks = await _catalog.build();
      await _hub.startSharing(tracks);
      if (mounted) setState(() => _tracks = tracks);
    } catch (error) {
      if (mounted) setState(() => _error = '启动传输服务失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (_busy || !_hub.isRunning) return;
    setState(() => _busy = true);
    try {
      await _hub.stopSharing();
    } catch (error) {
      if (mounted) setState(() => _error = '停止传输服务失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyPairing(MediaHubSession session) async {
    await Clipboard.setData(
      ClipboardData(text: session.pairingUri.toString()),
    );
    _showMessage('配对信息已复制，可以粘贴到手机端。');
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
        body: Center(child: Text('请在 Windows / macOS / Linux 桌面端打开此页面')),
      );
    }

    final layout = AppResponsive.of(context);
    final session = _hubState.session;
    final running = _hubState.isRunning;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text('电脑 ↔ 手机传输'),
        backgroundColor: AppColors.bgBase,
        actions: [
          IconButton(
            tooltip: '打开电脑本地音乐库',
            onPressed: () => Navigator.pushNamed(context, Routes.library),
            icon: const Icon(Icons.library_music_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: layout.contentMaxWidth),
            child: ListView(
              padding: EdgeInsets.all(layout.pageGutter),
              children: [
                _OverviewCard(
                  running: running,
                  initializing: _initializing,
                  busy: _busy,
                  trackCount: session?.trackCount ?? _tracks.length,
                  onStart: _start,
                  onStop: _stop,
                  onRefresh: _refreshAndRestart,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _ErrorCard(message: _error!),
                ],
                const SizedBox(height: AppSpacing.md),
                if (session != null && running)
                  _PairingCard(
                    session: session,
                    onCopy: () => _copyPairing(session),
                  )
                else
                  _WaitingForPairingCard(
                    initializing: _initializing ||
                        _hubState.status == MediaHubStatus.starting,
                    onStart: _start,
                  ),
                const SizedBox(height: AppSpacing.md),
                _DirectionCard(
                  icon: Icons.phone_iphone_rounded,
                  title: '电脑 → 手机',
                  subtitle: running
                      ? '电脑 Library 里的 ${session?.trackCount ?? _tracks.length} 首可用歌曲已经自动共享。手机扫码后可以在线播放，或选择“下载并播放”，下载完成后会进入手机本地音乐库。'
                      : '启动服务后，电脑本地音乐库会自动作为手机可下载列表。',
                ),
                const SizedBox(height: AppSpacing.md),
                _DirectionCard(
                  icon: Icons.computer_rounded,
                  title: '手机 → 电脑',
                  subtitle: running
                      ? '手机连接后可多选本机音频发送到电脑。文件完整传完后会保存到 LyricForge/Incoming，并自动加入电脑 Library；点右上角音乐库按钮即可直接播放。'
                      : '启动服务后，手机即可把本地音乐批量发送到这台电脑。',
                ),
                const SizedBox(height: AppSpacing.md),
                _SharedTracksCard(tracks: _tracks, running: running),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final bool running;
  final bool initializing;
  final bool busy;
  final int trackCount;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRefresh;

  const _OverviewCard({
    required this.running,
    required this.initializing,
    required this.busy,
    required this.trackCount,
    required this.onStart,
    required this.onStop,
    required this.onRefresh,
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: (running ? AppColors.success : AppColors.accent)
                        .withAlpha(20),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                  ),
                  child: Icon(
                    running ? Icons.sync_alt_rounded : Icons.devices_rounded,
                    color: running ? AppColors.success : AppColors.accent,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        running ? '电脑端已准备好配对' : '跨设备传输尚未启动',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        initializing
                            ? '正在读取电脑音乐库并启动传输服务…'
                            : running
                                ? '二维码就在下方。当前自动共享 $trackCount 首电脑本地音乐。'
                                : '启动后会立即生成二维码，并自动共享电脑本地音乐库。',
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
                  onPressed: busy || initializing
                      ? null
                      : running
                          ? onStop
                          : onStart,
                  icon: busy || initializing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded),
                  label: Text(running ? '停止传输服务' : '启动传输服务'),
                ),
                OutlinedButton.icon(
                  onPressed: busy || initializing ? null : onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('刷新电脑音乐库'),
                ),
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
  final VoidCallback onCopy;

  const _PairingCard({required this.session, required this.onCopy});

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
        size: layout.isCompact ? 180 : 220,
        backgroundColor: AppColors.pureWhite,
      ),
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '1. 用手机扫描这个二维码',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '手机端：跨设备传输 → 连接电脑 → 扫描桌面二维码。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          '2. 或复制下面的配对码',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          ),
          child: SelectableText(
            session.pairingUri.toString(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: onCopy,
          icon: const Icon(Icons.copy_rounded),
          label: const Text('复制配对码'),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('可连接地址', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        for (final endpoint in session.endpoints)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              '${endpoint.kind.name}: ${endpoint.host}:${endpoint.port}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
      ],
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: layout.isCompactOrMedium
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: qr),
                  const SizedBox(height: AppSpacing.lg),
                  details,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  qr,
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(child: details),
                ],
              ),
      ),
    );
  }
}

class _WaitingForPairingCard extends StatelessWidget {
  final bool initializing;
  final VoidCallback onStart;

  const _WaitingForPairingCard({
    required this.initializing,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            if (initializing)
              const CircularProgressIndicator()
            else
              const Icon(Icons.qr_code_2_rounded, size: 56, color: AppColors.accent),
            const SizedBox(height: AppSpacing.md),
            Text(initializing ? '正在生成配对二维码…' : '启动服务后显示配对二维码'),
            if (!initializing) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('启动并生成二维码'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DirectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _DirectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(AppSpacing.md),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.accent.withAlpha(18),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          ),
          child: Icon(icon, color: AppColors.accent),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
      ),
    );
  }
}

class _SharedTracksCard extends StatelessWidget {
  final List<SharedAudioTrack> tracks;
  final bool running;

  const _SharedTracksCard({required this.tracks, required this.running});

  @override
  Widget build(BuildContext context) {
    final visible = tracks.take(12).toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '电脑共享音乐 · ${tracks.length} 首',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Chip(label: Text(running ? '手机可访问' : '服务已停止')),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '这里直接来自电脑本地音乐库，不需要再重复选择文件。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (tracks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text('电脑 Library 还没有可用音乐。先导入音乐后，点击“刷新电脑音乐库”。'),
              )
            else ...[
              for (final track in visible)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.music_note_rounded),
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      if (track.artist?.isNotEmpty == true) track.artist!,
                      track.format.toUpperCase(),
                      _formatBytes(track.byteLength),
                    ].join(' · '),
                  ),
                ),
              if (tracks.length > visible.length)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    '另有 ${tracks.length - visible.length} 首未在此预览；手机端会看到完整列表。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.error_outline_rounded, color: AppColors.error),
        title: const Text('跨设备传输暂时不可用'),
        subtitle: Text(message),
      ),
    );
  }
}
