import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/navigation/transfer_entry.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_error_state.dart';
import '../../domain/models/media_hub_session.dart';
import '../../domain/models/shared_audio_track.dart';
import '../../domain/services/media_hub_service.dart';
import '../../domain/services/media_share_catalog.dart';
import '../transfer_screen_dependencies.dart';
import '../widgets/desktop_transfer_hub_cards.dart';
import '../widgets/desktop_transfer_hub_text.dart';

/// Desktop-first transfer center for an explicitly started Media Hub.
///
/// Opening this screen loads the preview of the computer's music library but
/// does not expose the network service until the user reviews and accepts
/// the HTTPS sharing scope. The cards live in `desktop_transfer_hub_cards.dart`
/// and the sentences in [DesktopTransferHubText].
class DesktopMediaTransferHubScreen extends StatefulWidget {
  final DesktopMediaHubDependencies dependencies;

  /// Title of the error state shown when a step fails.
  static const String failureTitle = DesktopTransferHubText.failureTitle;

  const DesktopMediaTransferHubScreen({super.key, required this.dependencies});

  @override
  State<DesktopMediaTransferHubScreen> createState() =>
      _DesktopMediaTransferHubScreenState();
}

class _DesktopMediaTransferHubScreenState
    extends State<DesktopMediaTransferHubScreen> {
  late final MediaHubService _hub;
  late final MediaShareCatalog _catalog;
  late MediaHubState _hubState;
  StreamSubscription<MediaHubState>? _hubSubscription;

  List<SharedAudioTrack> _tracks = const [];
  bool _busy = false;
  bool _initializing = true;

  /// The last failed step and how to run it again. The page used to show the
  /// message in its own error card with no way to retry; it now uses the
  /// shared [AppErrorState], whose 重试 repeats exactly the step that failed
  /// (reading the library, refreshing, starting or stopping the service).
  ({String message, Future<void> Function() retry})? _failure;

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    _hub = widget.dependencies.hub;
    _catalog = widget.dependencies.catalog;
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

      // Merely opening the transfer screen must never expose a network
      // listener. Starting Media Hub requires an explicit user action and
      // confirmation of the media-sharing scope.
    } catch (error) {
      _fail(DesktopTransferHubText.readFailed(error), _retryPrepare);
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<void> _retryPrepare() async {
    setState(() {
      _initializing = true;
      _failure = null;
    });
    await _prepare();
  }

  Future<void> _refreshAndRestart() async {
    if (_busy) return;

    // Refreshing a stopped service must not start listening as a side effect.
    // If the service is already running, require fresh consent before replacing
    // its session and invalidating the current pairing token.
    if (_hub.isRunning && !await _confirmMediaSharing()) return;
    if (!mounted) return;

    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final tracks = await _catalog.build();
      final wasRunning = _hub.isRunning;
      if (wasRunning) {
        await _hub.startSharing(tracks);
      }
      if (!mounted) return;
      setState(() => _tracks = tracks);
      _showMessage(
        wasRunning
            ? DesktopTransferHubText.refreshedRunning
            : DesktopTransferHubText.refreshedStopped,
      );
    } catch (error) {
      _fail(DesktopTransferHubText.refreshFailed(error), _refreshAndRestart);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (_busy || _hub.isRunning) return;
    if (!await _confirmMediaSharing() || !mounted) return;

    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final tracks = await _catalog.build();
      await _hub.startSharing(tracks);
      if (mounted) setState(() => _tracks = tracks);
    } catch (error) {
      _fail(DesktopTransferHubText.startFailed(error), _start);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fail(String message, Future<void> Function() retry) {
    if (!mounted) return;
    setState(() => _failure = (message: message, retry: retry));
  }

  /// The sharing scope the user agrees to before anything listens. Its
  /// wording stays here, beside the check, rather than in
  /// [DesktopTransferHubText]: `media_hub_security_consent_contract_test.dart`
  /// pins it in this file.
  Future<bool> _confirmMediaSharing() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('开启加密的网络共享？'),
        content: const Text(
          'Media Hub 通过证书指纹固定的 HTTPS 加密普通局域网和 Tailscale 连接。'
          '配对二维码会把桌面端证书指纹交给手机验证，避免仅凭网络地址信任服务器。'
          '启动后，已配对设备可以读取共享歌曲、歌词和封面，也可以向电脑上传音频。'
          '请只与可信设备配对；停止共享会关闭当前服务。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('暂不启用'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('我了解共享范围，继续'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _stop() async {
    if (_busy || !_hub.isRunning) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await _hub.stopSharing();
    } catch (error) {
      _fail(DesktopTransferHubText.stopFailed(error), _stop);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyPairing(MediaHubSession session) async {
    await Clipboard.setData(ClipboardData(text: session.pairingUri.toString()));
    _showMessage(DesktopTransferHubText.copied);
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

  void _openLibrary() => Navigator.pushNamed(context, Routes.library);

  /// What the waiting card says, or null when the service is simply off.
  String? get _waitingMessage {
    if (_initializing) return DesktopTransferHubText.libraryLoading;
    if (_hubState.status == MediaHubStatus.starting) {
      return DesktopTransferHubText.serviceStarting;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) return const _DesktopOnlyPage();

    final layout = AppResponsive.of(context);
    final session = _hubState.session;
    final running = _hubState.isRunning;
    final failure = _failure;
    final working = _busy || _initializing;
    final trackCount = session?.trackCount ?? _tracks.length;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text(TransferEntry.label),
        backgroundColor: AppColors.bgBase,
        actions: [
          IconButton(
            tooltip: DesktopTransferHubText.openLibraryTooltip,
            onPressed: _openLibrary,
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
                const DesktopHubSecurityNotice(),
                const SizedBox(height: AppSpacing.md),
                DesktopHubOverviewCard(
                  running: running,
                  initializing: _initializing,
                  busy: _busy,
                  trackCount: trackCount,
                  onStart: _start,
                  onStop: _stop,
                  onRefresh: _refreshAndRestart,
                ),
                if (failure != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Card(
                    child: AppErrorState(
                      title: DesktopMediaTransferHubScreen.failureTitle,
                      message: failure.message,
                      density: AppEmptyStateDensity.panel,
                      onRetry: working
                          ? null
                          : () => unawaited(failure.retry()),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                if (session != null && running)
                  DesktopHubPairingCard(
                    session: session,
                    onCopy: () => _copyPairing(session),
                  )
                else
                  DesktopHubWaitingCard(
                    loadingMessage: _waitingMessage,
                    onStart: working ? null : _start,
                  ),
                const SizedBox(height: AppSpacing.md),
                DesktopHubDirectionCard(
                  icon: Icons.phone_iphone_rounded,
                  title: DesktopTransferHubText.toPhoneTitle,
                  subtitle: running
                      ? DesktopTransferHubText.toPhoneRunning(trackCount)
                      : DesktopTransferHubText.toPhoneStopped,
                ),
                const SizedBox(height: AppSpacing.md),
                DesktopHubDirectionCard(
                  icon: Icons.computer_rounded,
                  title: DesktopTransferHubText.toComputerTitle,
                  subtitle: running
                      ? DesktopTransferHubText.toComputerRunning
                      : DesktopTransferHubText.toComputerStopped,
                ),
                const SizedBox(height: AppSpacing.md),
                DesktopHubSharedTracksCard(
                  tracks: _tracks,
                  running: running,
                  loading: _initializing,
                  onRefresh: working ? null : _refreshAndRestart,
                  onOpenLibrary: _openLibrary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// On a phone or the web this page has nothing to start; it says where
/// transfer starts instead and offers the phone's own way in. It was one
/// line of text on an empty page.
class _DesktopOnlyPage extends StatelessWidget {
  const _DesktopOnlyPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text(TransferEntry.label),
        backgroundColor: AppColors.bgBase,
      ),
      body: AppEmptyState(
        icon: Icons.desktop_windows_outlined,
        title: DesktopTransferHubText.desktopOnlyTitle,
        message: DesktopTransferHubText.desktopOnlyMessage,
        actions: [
          FilledButton.icon(
            onPressed: () => Navigator.pushReplacementNamed(
              context,
              TransferEntry.routeFor(desktop: false),
            ),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text(DesktopTransferHubText.connectFromPhone),
          ),
        ],
      ),
    );
  }
}
