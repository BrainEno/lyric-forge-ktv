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
      metadataRepository: services.localMediaMetadataRepository,
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
      if (!mounted) return;
      setState(() => _tracks = tracks);
    } catch (error) {
      if (mounted) setState(() => _error = '启动失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (_busy || !_hub.isRunning) return;
    setState(() => _busy = true);
    try {
      await _hub.stopSharing();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _copyPairingUri(MediaHubSession session) {
    Clipboard.setData(ClipboardData(text: session.pairingUri.toString()));
    _showMessage('配对信息已复制');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final session = _hubState.session;
    final running = _hubState.isRunning && session != null;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        title: const Text('跨设备传输'),
        actions: [
          if (running)
            IconButton(
              tooltip: '刷新电脑音乐库',
              onPressed: _busy ? null : _refreshAndRestart,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: !_isDesktop
            ? const Center(child: Text('请在桌面端使用跨设备传输中心'))
            : Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: layout.contentMaxWidth),
                  child: ListView(
                    padding: EdgeInsets.all(layout.pageGutter),
                    children: [
                      _StatusCard(
                        running: running,
                        trackCount: _tracks.length,
                        busy: _busy || _initializing,
                        error: _error,
                        onStart: _start,
                        onStop: _stop,
                      ),
                      SizedBox(height: layout.sectionGap),
                      if (running && session != null)
                        _PairingCard(
                          session: session,
                          onCopy: () => _copyPairingUri(session),
                        )
                      else if (_initializing)
                        const Center(child: CircularProgressIndicator()),
                      if (running && session != null) ...[
                        SizedBox(height: layout.sectionGap),
                        _ConnectionHints(session: session),
                      ],
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
  final int trackCount;
  final bool busy;
  final String? error;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const _StatusCard({
    required this.running,
    required this.trackCount,
    required this.busy,
    required this.error,
    required this.onStart,
    required this.onStop,
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
                  running ? Icons.wifi_tethering_rounded : Icons.devices_rounded,
                  size: 34,
                  color: running ? AppColors.success : AppColors.accent,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        running ? '电脑端已准备好配对' : '跨设备传输尚未启动',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        running
                            ? '$trackCount 首本地音乐已共享给已配对设备'
                            : '启动后，手机可以浏览、在线播放或下载桌面音乐库。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                if (running)
                  OutlinedButton.icon(
                    onPressed: busy ? null : onStop,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('停止'),
                  )
                else
                  FilledButton.icon(
                    onPressed: busy ? null : onStart,
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(busy ? '正在启动...' : '启动'),
                  ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(error!, style: const TextStyle(color: AppColors.error)),
            ],
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
    final pairingUri = session.pairingUri.toString();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 220,
              height: 220,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.pureWhite,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
              ),
              child: QrImageView(
                data: pairingUri,
                backgroundColor: AppColors.pureWhite,
                eyeStyle: const QrEyeStyle(color: AppColors.pureBlack),
                dataModuleStyle:
                    const QrDataModuleStyle(color: AppColors.pureBlack),
              ),
            ),
            const SizedBox(width: AppSpacing.xl),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '用手机扫描二维码',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '手机端：跨设备传输 → 连接电脑 → 扫描桌面二维码。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SelectableText(
                    pairingUri,
                    maxLines: 5,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                          fontFamily: 'monospace',
                        ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('复制配对信息'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionHints extends StatelessWidget {
  final MediaHubSession session;

  const _ConnectionHints({required this.session});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '连接方式',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final endpoint in session.endpoints)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  endpoint.kind == MediaHubEndpointKind.tailscale
                      ? Icons.public_rounded
                      : Icons.wifi_rounded,
                  color: endpoint.kind == MediaHubEndpointKind.tailscale
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ),
                title: Text('${endpoint.host}:${endpoint.port}'),
                subtitle: Text(
                  endpoint.kind == MediaHubEndpointKind.tailscale
                      ? 'Tailscale · 可跨网络访问'
                      : endpoint.kind == MediaHubEndpointKind.lan
                          ? '局域网'
                          : '其他网络接口',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
