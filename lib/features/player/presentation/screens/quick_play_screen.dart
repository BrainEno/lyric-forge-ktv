import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/play_history.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/repositories/play_history_repository.dart';
import '../../domain/services/audio_player_service.dart';

/// Local music player for audio that is not attached to a LyricForge project.
///
/// This intentionally behaves like a normal player. Creating a lyric project is
/// a separate workflow rather than a special "quick play" mode.
class QuickPlayScreen extends StatefulWidget {
  final PlayHistory? initialHistory;

  const QuickPlayScreen({
    super.key,
    this.initialHistory,
  });

  @override
  State<QuickPlayScreen> createState() => _QuickPlayScreenState();
}

class _QuickPlayScreenState extends State<QuickPlayScreen> {
  static const _supportedExtensions = {
    'mp3',
    'flac',
    'wav',
    'm4a',
    'aac',
    'ogg',
  };

  late final AudioPlayerService _audioService;
  late final PlayHistoryRepository _playHistoryRepository;

  File? _selectedFile;
  String? _activeHistoryId;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _audioService = ServiceLocatorGlobal.I.audioPlayerService;
    _playHistoryRepository = ServiceLocatorGlobal.I.playHistoryRepository;

    if (widget.initialHistory != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadHistory(widget.initialHistory!);
      });
    }
  }

  Future<void> _loadHistory(PlayHistory history) async {
    final file = File(history.filePath);
    if (!await file.exists()) {
      if (!mounted) return;
      setState(() {
        _error = '找不到这首音乐的本地文件，可能已被移动或删除。';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _selectedFile = file;
      _activeHistoryId = history.id;
      _error = null;
    });
    await _loadAndPlay(file, resumeFrom: history.lastPosition);
  }

  Future<void> _pickAudioFile() async {
    try {
      final useUnfilteredMacPicker = Platform.isMacOS;
      final result = await FilePicker.platform.pickFiles(
        // Keep macOS navigation unfiltered. Some native picker combinations can
        // make folders look disabled when extension filters are applied.
        type: useUnfilteredMacPicker ? FileType.any : FileType.custom,
        allowedExtensions: useUnfilteredMacPicker
            ? null
            : _supportedExtensions.toList(growable: false),
        allowMultiple: false,
        dialogTitle: '选择音频文件',
        allowCompression: false,
        withData: false,
        withReadStream: false,
      );

      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path;
      if (path == null) {
        if (!mounted) return;
        setState(() => _error = '无法获取文件路径');
        return;
      }

      final extension = _getFileExtension(path);
      if (!_supportedExtensions.contains(extension)) {
        if (!mounted) return;
        setState(() {
          _error = '请选择 MP3 / FLAC / WAV / M4A / AAC / OGG 音频文件';
        });
        return;
      }

      final file = File(path);
      if (!mounted) return;
      setState(() {
        _selectedFile = file;
        _activeHistoryId = null;
        _error = null;
      });
      await _loadAndPlay(file);
    } catch (error, stackTrace) {
      debugPrint('File picker error: $error');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() => _error = '无法选择文件: $error');
    }
  }

  Future<void> _loadAndPlay(
    File file, {
    Duration? resumeFrom,
  }) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final audioAsset = AudioAsset(
        originalPath: file.path,
        format: _getFileExtension(file.path),
      );
      await _audioService.loadProjectAudio(
        audioAsset: audioAsset,
        preferredSource: AudioSourceType.original,
      );

      if (resumeFrom != null && resumeFrom > Duration.zero) {
        final duration = _audioService.currentState.duration;
        if (duration == null || resumeFrom < duration) {
          await _audioService.seek(resumeFrom);
        }
      }

      await _audioService.play();
      await _savePlayHistory(file);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '无法播放文件: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _savePlayHistory(File file) async {
    try {
      final fileName = _getFileName(file.path);
      final name = fileName.replaceAll(
        RegExp(r'\.(mp3|flac|wav|m4a|ogg|aac)$', caseSensitive: false),
        '',
      );
      final state = _audioService.currentState;
      final id = _activeHistoryId ?? const Uuid().v4();
      _activeHistoryId = id;

      await _playHistoryRepository.savePlayHistory(
        PlayHistory(
          id: id,
          name: name,
          filePath: file.path,
          playedAt: DateTime.now(),
          lastPosition: state.position,
          duration: state.duration,
          lastSource: AudioSourceType.original,
        ),
      );
    } catch (error) {
      debugPrint('Failed to save play history: $error');
    }
  }

  String _getFileExtension(String path) {
    final parts = path.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  String _getFileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  String _displayTitle(String path) {
    return _getFileName(path).replaceAll(
      RegExp(r'\.(mp3|flac|wav|m4a|ogg|aac)$', caseSensitive: false),
      '',
    );
  }

  Future<void> _playPause() async {
    final state = _audioService.currentState;
    if (state.isPlaying) {
      await _audioService.pause();
    } else {
      await _audioService.play();
    }
  }

  Future<void> _seek(Duration position) => _audioService.seek(position);

  Future<void> _skip(Duration delta) async {
    final state = _audioService.currentState;
    final duration = state.duration;
    var target = state.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (duration != null && target > duration) target = duration;
    await _audioService.seek(target);
  }

  Future<void> _setVolume(double value) => _audioService.setVolume(value);

  void _showKtvHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('这首音乐还没有歌词工程。新建工程并完成歌词识别后即可进入 KTV 模式。'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = _selectedFile;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: Text(file == null ? '本地播放器' : '正在播放'),
        backgroundColor: AppColors.bgBase,
        actions: [
          if (file != null)
            IconButton(
              onPressed: _pickAudioFile,
              icon: const Icon(Icons.folder_open_rounded),
              tooltip: '打开其他音乐',
            ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: file == null
            ? _FileSelectionState(
                onPickFile: _pickAudioFile,
                onCreateProject: () =>
                    Navigator.pushNamed(context, Routes.import),
                error: _error,
              )
            : _PlayerState(
                audioService: _audioService,
                title: _displayTitle(file.path),
                format: _getFileExtension(file.path).toUpperCase(),
                error: _error,
                isLoading: _isLoading,
                onPlayPause: _playPause,
                onSeek: _seek,
                onSkipBack: () => _skip(const Duration(seconds: -10)),
                onSkipForward: () => _skip(const Duration(seconds: 10)),
                onVolumeChanged: _setVolume,
                onKtvTap: _showKtvHint,
              ),
      ),
    );
  }

  @override
  void dispose() {
    _audioService.stop();
    super.dispose();
  }
}

class _FileSelectionState extends StatelessWidget {
  final VoidCallback onPickFile;
  final VoidCallback onCreateProject;
  final String? error;

  const _FileSelectionState({
    required this.onPickFile,
    required this.onCreateProject,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 148,
                height: 148,
                decoration: BoxDecoration(
                  gradient: AppColors.cardGradient,
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusXLarge),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(70),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.library_music_rounded,
                  size: 64,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                '打开一首本地音乐',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '直接试听，不创建工程。支持 MP3、FLAC、WAV、M4A、AAC 和 OGG。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              if (error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: onPickFile,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('选择音乐'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: onCreateProject,
                icon: const Icon(Icons.lyrics_rounded),
                label: const Text('需要识别歌词？新建工程'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerState extends StatelessWidget {
  final AudioPlayerService audioService;
  final String title;
  final String format;
  final String? error;
  final bool isLoading;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onKtvTap;

  const _PlayerState({
    required this.audioService,
    required this.title,
    required this.format,
    required this.error,
    required this.isLoading,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSkipBack,
    required this.onSkipForward,
    required this.onVolumeChanged,
    required this.onKtvTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: audioService.stateStream,
      initialData: audioService.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? const PlaybackState.idle();

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 920;
            final artwork = _Artwork(isLoading: isLoading || state.isLoading);
            final controls = _PlayerControls(
              title: title,
              format: format,
              state: state,
              error: error ?? state.error,
              onPlayPause: onPlayPause,
              onSeek: onSeek,
              onSkipBack: onSkipBack,
              onSkipForward: onSkipForward,
              onVolumeChanged: onVolumeChanged,
              onKtvTap: onKtvTap,
            );

            if (!wide) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: artwork,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    controls,
                  ],
                ),
              );
            }

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(width: 380, child: artwork),
                      const SizedBox(width: AppSpacing.xxxl),
                      Expanded(child: controls),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Artwork extends StatelessWidget {
  final bool isLoading;

  const _Artwork({required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(82),
              blurRadius: 32,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Center(
          child: isLoading
              ? const CircularProgressIndicator()
              : const Icon(
                  Icons.album_rounded,
                  size: 112,
                  color: AppColors.textSecondary,
                ),
        ),
      ),
    );
  }
}

class _PlayerControls extends StatelessWidget {
  final String title;
  final String format;
  final PlaybackState state;
  final String? error;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onKtvTap;

  const _PlayerControls({
    required this.title,
    required this.format,
    required this.state,
    required this.error,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSkipBack,
    required this.onSkipForward,
    required this.onVolumeChanged,
    required this.onKtvTap,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '本地音乐',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$format · 暂无歌词',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(error!, style: const TextStyle(color: AppColors.error)),
          ],
          const SizedBox(height: AppSpacing.xl),
          _ProgressBar(state: state, onSeek: onSeek),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: onSkipBack,
                tooltip: '后退 10 秒',
                icon: const Icon(Icons.replay_10_rounded),
                iconSize: 30,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.lg),
              _PlayPauseButton(
                isPlaying: state.isPlaying,
                isBuffering: state.isBuffering || state.isLoading,
                onPressed: onPlayPause,
              ),
              const SizedBox(width: AppSpacing.lg),
              IconButton(
                onPressed: onSkipForward,
                tooltip: '前进 10 秒',
                icon: const Icon(Icons.forward_10_rounded),
                iconSize: 30,
                color: AppColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              const Icon(
                Icons.volume_down_rounded,
                size: 20,
                color: AppColors.textTertiary,
              ),
              Expanded(
                child: Slider(
                  value: state.volume.clamp(0.0, 1.0),
                  min: 0,
                  max: 1,
                  onChanged: onVolumeChanged,
                ),
              ),
              const Icon(
                Icons.volume_up_rounded,
                size: 20,
                color: AppColors.textTertiary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(color: AppColors.borderSubtle),
          const SizedBox(height: AppSpacing.md),
          Tooltip(
            message: '需要先创建歌词工程并完成识别',
            child: OutlinedButton.icon(
              onPressed: onKtvTap,
              icon: const Icon(Icons.mic_rounded),
              label: const Text('KTV 模式'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final PlaybackState state;
  final ValueChanged<Duration> onSeek;

  const _ProgressBar({
    required this.state,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final duration = state.duration;
    final max = duration?.inMilliseconds.toDouble() ?? 1.0;
    final value = state.position.inMilliseconds.toDouble().clamp(0.0, max);

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: AppColors.pureWhite,
            inactiveTrackColor: AppColors.bgHighlight,
            thumbColor: AppColors.pureWhite,
            overlayColor: AppColors.hoverOverlay,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value,
            min: 0,
            max: max,
            onChanged: duration == null
                ? null
                : (next) => onSeek(
                      Duration(milliseconds: next.round()),
                    ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              state.formattedPosition,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
            Text(
              state.formattedDuration,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final bool isBuffering;
  final VoidCallback onPressed;

  const _PlayPauseButton({
    required this.isPlaying,
    required this.isBuffering,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: IconButton(
        onPressed: isBuffering ? null : onPressed,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.pureWhite,
          disabledBackgroundColor: AppColors.textDisabled,
          foregroundColor: AppColors.pureBlack,
        ),
        icon: isBuffering
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.pureBlack,
                ),
              )
            : Icon(
                isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 34,
              ),
      ),
    );
  }
}
