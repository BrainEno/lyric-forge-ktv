import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/diagnostics/app_build_info.dart';
import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/playback_destination.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/navigation/transfer_entry.dart';
import '../dashboard_dependencies.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/models/play_history.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../player/domain/repositories/play_history_repository.dart';
import '../../../player/domain/services/audio_player_service.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../../transcription/domain/models/transcription_queue_models.dart';
import '../../../transcription/domain/models/transcription_models.dart';
import '../../../transcription/domain/services/batch_transcription_queue.dart';
import '../../../transcription/domain/services/transcription_settings_store.dart';
import '../../../transcription/presentation/widgets/transcription_config_dialog.dart';
import '../widgets/dashboard_background_work_card.dart';
import '../widgets/dashboard_now_playing.dart';
import '../widgets/dashboard_shelves.dart';

class DashboardScreen extends StatefulWidget {
  final DashboardDependencies dependencies;

  const DashboardScreen({super.key, required this.dependencies});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final ProjectRepository _projects;
  late final PlayHistoryRepository _history;
  late final PlaybackSessionService _playbackSession;
  late final AudioPlayerService _audioPlayer;
  late final BatchTranscriptionQueue _transcriptionQueue;
  late final TranscriptionSettingsStore _transcriptionSettingsStore;
  late Future<List<ProjectManifest>> _projectsFuture;
  late Future<List<PlayHistory>> _historyFuture;
  StreamSubscription<void>? _projectChanges;

  @override
  void initState() {
    super.initState();
    _projectChanges = widget.dependencies.projectChanges?.listen((_) {
      if (mounted) _refresh();
    });
    _projects = widget.dependencies.projectRepository;
    _history = widget.dependencies.playHistoryRepository;
    _playbackSession = widget.dependencies.playbackSession;
    _audioPlayer = widget.dependencies.audioPlayer;
    _transcriptionQueue = widget.dependencies.transcriptionQueue;
    _transcriptionSettingsStore =
        widget.dependencies.transcriptionSettingsStore;
    _loadData();
  }

  void _loadData() {
    _projectsFuture = _observeUntilBuild(_projects.getRecentProjects(limit: 8));
    _historyFuture = _observeUntilBuild(
      _history.getRecentPlayHistory(limit: 10),
    );
  }

  Future<T> _observeUntilBuild<T>(Future<T> future) {
    // A refresh can fail before FutureBuilder subscribes on the next frame.
    // Observe that early error without changing the future the UI receives.
    future.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return future;
  }

  Future<void> _refresh() async => setState(_loadData);

  @override
  void dispose() {
    _projectChanges?.cancel();
    super.dispose();
  }

  Future<void> _openModelSettings() async {
    try {
      final initialConfig =
          await _transcriptionSettingsStore.load() ??
          const TranscriptionConfig(
            mode: TranscriptionMode.highestQuality,
            profilePreference: TranscriptionProfilePreference.automatic,
            qwenExecutable: 'qwen3-asr',
            whisperExecutable: 'whisper-cli',
            modelPath: '',
          );
      if (!mounted) return;
      final updated = await showDialog<TranscriptionConfig>(
        context: context,
        builder: (context) => TranscriptionConfigDialog(
          initialConfig: initialConfig,
          dependencies: widget.dependencies.configDialogDependencies,
        ),
      );
      if (updated == null || !mounted) return;
      if (updated.isConfigured) {
        await _transcriptionSettingsStore.save(updated);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('打开模型高级设置失败：$error')));
    }
  }

  // Three intents, three routes (audit N-01). They all used to push
  // `/quick-play` and let the router pick a screen from whatever was playing.

  /// 打开音乐 / 选择音乐: picking something to play happens in the library.
  Future<void> _openMusic() async {
    await Navigator.pushNamed(context, Routes.library);
    if (mounted) _refresh();
  }

  /// A project page or 全部工程; a project may be gone when the user
  /// comes back (D-063).
  Future<void> _openRoute(String route) async {
    await Navigator.pushNamed(context, route);
    if (mounted) _refresh();
  }

  /// A recent song: the local player resumes that history entry.
  Future<void> _resumeHistory(PlayHistory history) async {
    await Navigator.pushNamed(
      context,
      PlaybackDestination.localPlayer.routeName(),
      arguments: history,
    );
    if (mounted) _refresh();
  }

  /// The playing hero: the player that fits the current song.
  void _openCurrent(PlaybackItem item) {
    final destination = PlaybackDestination.resolve(
      hasCurrent: true,
      projectId: item.projectId,
      isRemoteStream: item.isRemoteStream,
    );
    Navigator.pushNamed(
      context,
      destination.routeName(projectId: item.projectId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final verticalStart = layout.isShort ? AppSpacing.sm : AppSpacing.md;
    final bottomPadding = layout.isCompact ? AppSpacing.xxl : AppSpacing.xxxl;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: StreamBuilder<PlaybackSessionState>(
          stream: _playbackSession.stateStream,
          initialData: _playbackSession.currentState,
          builder: (context, sessionSnapshot) {
            final session =
                sessionSnapshot.data ?? const PlaybackSessionState();
            return StreamBuilder<PlaybackState>(
              stream: _audioPlayer.stateStream,
              initialData: _audioPlayer.currentState,
              builder: (context, playbackSnapshot) {
                final playback =
                    playbackSnapshot.data ?? const PlaybackState.idle();
                return StreamBuilder<TranscriptionQueueSnapshot>(
                  stream: _transcriptionQueue.snapshots,
                  initialData: _transcriptionQueue.current,
                  builder: (context, queueSnapshot) {
                    final queue =
                        queueSnapshot.data ??
                        const TranscriptionQueueSnapshot(
                          items: [],
                          isPaused: false,
                          isProcessing: false,
                        );
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      color: AppColors.accent,
                      backgroundColor: AppColors.bgElevated,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: layout.contentMaxWidth,
                            ),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                layout.pageGutter,
                                verticalStart,
                                layout.pageGutter,
                                bottomPadding,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _Header(
                                    // The idle hero already offers this.
                                    showOpenMusic: session.currentItem != null,
                                    onOpenMusic: _openMusic,
                                    onImport: () => Navigator.pushNamed(
                                      context,
                                      Routes.import,
                                    ),
                                    onOpenTransfer: () =>
                                        TransferEntry.open(context),
                                    onOpenModelSettings: _openModelSettings,
                                    onOpenSettings: () => Navigator.pushNamed(
                                      context,
                                      Routes.settings,
                                    ),
                                  ),
                                  SizedBox(height: layout.sectionGap),
                                  DashboardNowPlayingArea(
                                    session: session,
                                    playback: playback,
                                    onOpenMusic: _openMusic,
                                    onOpenCurrent: _openCurrent,
                                    onPlayPause:
                                        _playbackSession.togglePlayPause,
                                    onPrevious: _playbackSession.skipPrevious,
                                    onNext: _playbackSession.skipNext,
                                    onPlayQueueItem: _playbackSession.playItem,
                                  ),
                                  if (queue.items.isNotEmpty) ...[
                                    SizedBox(height: layout.sectionGap),
                                    DashboardBackgroundWorkCard(
                                      snapshot: queue,
                                      onOpen: () => Navigator.pushNamed(
                                        context,
                                        Routes.import,
                                      ),
                                      onPauseResume: queue.isPaused
                                          ? _transcriptionQueue.resume
                                          : _transcriptionQueue.pause,
                                    ),
                                  ],
                                  SizedBox(
                                    height: layout.isCompact
                                        ? AppSpacing.xl
                                        : AppSpacing.xxxl,
                                  ),
                                  const DashboardSectionHeader(
                                    title: '最近播放',
                                    subtitle: '继续你最近听过的本地音乐',
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  FutureBuilder<List<PlayHistory>>(
                                    future: _historyFuture,
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return DashboardLoadingBlock(
                                          height: layout.isCompact ? 170 : 190,
                                        );
                                      }
                                      if (snapshot.hasError) {
                                        return DashboardEmptyCard(
                                          isError: true,
                                          icon: Icons.error_outline_rounded,
                                          title: '播放记录加载失败',
                                          message: '播放记录暂时无法读取，可以重新加载一次。',
                                          action: '重试',
                                          onAction: _refresh,
                                        );
                                      }
                                      final items = snapshot.data ?? [];
                                      if (items.isEmpty) {
                                        return DashboardEmptyCard(
                                          icon: Icons.headphones_rounded,
                                          title: '还没有播放记录',
                                          message: '打开一首本地音乐后，会从这里快速继续。',
                                          action: session.currentItem == null
                                              ? null
                                              : '选择音乐',
                                          onAction: _openMusic,
                                        );
                                      }
                                      return DashboardRecentShelf(
                                        histories: items,
                                        onPlay: _resumeHistory,
                                      );
                                    },
                                  ),
                                  SizedBox(
                                    height: layout.isCompact
                                        ? AppSpacing.xl
                                        : AppSpacing.xxxl,
                                  ),
                                  // Every project, deleting and duplicate
                                  // cleanup live on 全部工程 (D-063); import
                                  // stays in the header.
                                  DashboardSectionHeader(
                                    title: '最近工程',
                                    subtitle: '继续识别、校对，或打开已经准备好的 KTV 工程',
                                    action: '全部工程',
                                    onAction: () => _openRoute(Routes.projects),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  FutureBuilder<List<ProjectManifest>>(
                                    future: _projectsFuture,
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return DashboardLoadingBlock(
                                          height: layout.isCompact ? 220 : 260,
                                        );
                                      }
                                      if (snapshot.hasError) {
                                        return DashboardEmptyCard(
                                          isError: true,
                                          icon: Icons.error_outline_rounded,
                                          title: '最近工程加载失败',
                                          message: '工程文件暂时无法读取，可以重新加载一次。',
                                          action: '重试',
                                          onAction: _refresh,
                                        );
                                      }
                                      final items = snapshot.data ?? [];
                                      if (items.isEmpty) {
                                        return DashboardEmptyCard(
                                          icon: Icons.auto_awesome_rounded,
                                          title: '还没有歌词工程',
                                          message:
                                              '导入歌曲后，Elysium Player 会在后台逐首识别并保存工程。',
                                          action: '导入歌曲',
                                          onAction: () => Navigator.pushNamed(
                                            context,
                                            Routes.import,
                                          ),
                                        );
                                      }
                                      return DashboardProjectGrid(
                                        projects: items,
                                        onOpen: (project) => _openRoute(
                                          Routes.projectDetailPath(project.id),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Page title and the global actions.
///
/// 打开音乐 used to appear here, in the idle hero, beside 最近播放 and on the
/// empty history card at the same time (audit C-01). The header now offers it
/// only while something is playing, when the hero shows the current song
/// instead of its own button.
class _Header extends StatelessWidget {
  final bool showOpenMusic;
  final VoidCallback onOpenMusic;
  final VoidCallback onImport;

  /// 跨设备传输 in the 更多 menu. The header used to have its own 远程音乐库
  /// button for it on desktop (audit L-02).
  final VoidCallback onOpenTransfer;
  final VoidCallback onOpenModelSettings;
  final VoidCallback onOpenSettings;

  const _Header({
    required this.showOpenMusic,
    required this.onOpenMusic,
    required this.onImport,
    required this.onOpenTransfer,
    required this.onOpenModelSettings,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppResponsive.fromConstraints(constraints);
        final compact = layout.isCompactOrMedium || layout.isShort;
        final name = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appDisplayName,
              style:
                  (layout.isCompact
                          ? Theme.of(context).textTheme.headlineSmall
                          : Theme.of(context).textTheme.headlineMedium)
                      ?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                      ),
            ),
            const SizedBox(height: 2),
            Text(
              '你的本地音乐、歌词与 KTV 工作台',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        );
        // The header is the product's name alone: the embedded brand mark
        // was removed everywhere at the user's request (D-049).
        final identity = name;
        final actions = Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (showOpenMusic)
              OutlinedButton.icon(
                key: const ValueKey('dashboard:header-open-music'),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(
                    layout.minimumInteractiveExtent,
                    layout.minimumInteractiveExtent,
                  ),
                ),
                onPressed: onOpenMusic,
                icon: const Icon(Icons.library_music_rounded, size: 18),
                label: const Text('打开音乐'),
              ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: Size(
                  layout.minimumInteractiveExtent,
                  layout.minimumInteractiveExtent,
                ),
              ),
              onPressed: onImport,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(layout.isCompact ? '识别歌词' : '导入并识别'),
            ),
            SizedBox(
              width: layout.minimumInteractiveExtent,
              height: layout.minimumInteractiveExtent,
              child: PopupMenuButton<String>(
                tooltip: '更多',
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (value) {
                  switch (value) {
                    case TransferEntry.menuValue:
                      onOpenTransfer();
                      break;
                    case 'modelSettings':
                      onOpenModelSettings();
                      break;
                    case 'settings':
                      onOpenSettings();
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: TransferEntry.menuValue,
                    child: Row(
                      children: [
                        Icon(TransferEntry.icon, size: 18),
                        SizedBox(width: AppSpacing.sm),
                        Text(TransferEntry.label),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'modelSettings',
                    child: Row(
                      children: [
                        Icon(Icons.tune_rounded, size: 18),
                        SizedBox(width: AppSpacing.sm),
                        Text('模型高级设置'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'settings',
                    child: Row(
                      children: [
                        Icon(Icons.settings_outlined, size: 18),
                        SizedBox(width: AppSpacing.sm),
                        Text('应用设置'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        return compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  identity,
                  const SizedBox(height: AppSpacing.md),
                  actions,
                ],
              )
            : Row(
                children: [
                  Expanded(child: identity),
                  actions,
                ],
              );
      },
    );
  }
}
