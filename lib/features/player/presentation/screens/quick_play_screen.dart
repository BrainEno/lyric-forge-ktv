import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/play_history.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/repositories/play_history_repository.dart';
import '../../domain/services/audio_player_service.dart';

/// Quick Play screen - direct audio playback without creating a project.
/// Desktop-first: select audio file and play immediately.
class QuickPlayScreen extends StatefulWidget {
  const QuickPlayScreen({super.key});

  @override
  State<QuickPlayScreen> createState() => _QuickPlayScreenState();
}

class _QuickPlayScreenState extends State<QuickPlayScreen> {
  late final AudioPlayerService _audioService;
  late final PlayHistoryRepository _playHistoryRepository;
  File? _selectedFile;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _audioService = ServiceLocatorGlobal.I.audioPlayerService;
    _playHistoryRepository = ServiceLocatorGlobal.I.playHistoryRepository;
  }

  Future<void> _pickAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        setState(() {
          _selectedFile = file;
          _error = null;
        });
        await _loadAndPlay(file);
      }
    } catch (e) {
      setState(() {
        _error = '无法选择文件: $e';
      });
    }
  }

  Future<void> _loadAndPlay(File file) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Create a temporary AudioAsset for the file
      final audioAsset = AudioAsset(
        originalPath: file.path,
        format: _getFileExtension(file.path),
      );

      await _audioService.loadProjectAudio(
        audioAsset: audioAsset,
        preferredSource: AudioSourceType.original,
      );
      await _audioService.play();

      // Save to play history
      await _savePlayHistory(file);
    } catch (e) {
      setState(() {
        _error = '无法播放文件: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _savePlayHistory(File file) async {
    try {
      final fileName = _getFileName(file.path);
      // Remove file extension for display name
      final name = fileName.replaceAll(
        RegExp(r'\.(mp3|flac|wav|m4a|ogg|aac)$', caseSensitive: false),
        '',
      );

      final history = PlayHistory(
        id: const Uuid().v4(),
        name: name,
        filePath: file.path,
        playedAt: DateTime.now(),
        lastSource: AudioSourceType.original,
      );

      await _playHistoryRepository.savePlayHistory(history);
    } catch (e) {
      // Silently fail - play history is not critical
      debugPrint('Failed to save play history: $e');
    }
  }

  String _getFileExtension(String path) {
    final parts = path.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  String _getFileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  Future<void> _playPause() async {
    final state = _audioService.currentState;
    if (state.isPlaying) {
      await _audioService.pause();
    } else {
      await _audioService.play();
    }
  }

  Future<void> _seek(Duration position) async {
    await _audioService.seek(position);
  }

  Future<void> _stop() async {
    await _audioService.stop();
    setState(() {
      _selectedFile = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text('快速播放'),
        backgroundColor: AppColors.bgBase,
        actions: [
          if (_selectedFile != null)
            IconButton(
              onPressed: _stop,
              icon: const Icon(Icons.close),
              tooltip: '停止播放',
            ),
        ],
      ),
      body: SafeArea(
        child: _selectedFile == null
            ? _FileSelectionState(
                onPickFile: _pickAudioFile,
                error: _error,
              )
            : _PlayerState(
                audioService: _audioService,
                fileName: _getFileName(_selectedFile!.path),
                isLoading: _isLoading,
                onPlayPause: _playPause,
                onSeek: _seek,
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
  final String? error;

  const _FileSelectionState({
    required this.onPickFile,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: AppSpacing.xxl * 3,
            height: AppSpacing.xxl * 3,
            decoration: BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
              border: Border.all(
                color: AppColors.borderSubtle,
                width: 2,
              ),
            ),
            child: Icon(
              Icons.music_note_outlined,
              size: 64,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '选择音频文件',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '支持 MP3 / FLAC / WAV / M4A 格式',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(26),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
              ),
              child: Text(
                error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.error,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          ElevatedButton.icon(
            onPressed: onPickFile,
            icon: const Icon(Icons.folder_open),
            label: const Text('浏览文件'),
          ),
        ],
      ),
    );
  }
}

class _PlayerState extends StatelessWidget {
  final AudioPlayerService audioService;
  final String fileName;
  final bool isLoading;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;

  const _PlayerState({
    required this.audioService,
    required this.fileName,
    required this.isLoading,
    required this.onPlayPause,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: audioService.stateStream,
      initialData: audioService.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? const PlaybackState.idle();

        return Column(
          children: [
            // Album artwork area
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(77),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      color: AppColors.bgSurface,
                      child: Center(
                        child: Icon(
                          Icons.album,
                          size: 100,
                          color: isLoading
                              ? AppColors.accent
                              : AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // File info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                children: [
                  Text(
                    fileName,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '快速播放模式',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            // Progress bar
            _QuickPlayProgressBar(
              state: state,
              onSeek: onSeek,
            ),

            const SizedBox(height: AppSpacing.lg),

            // Controls
            _QuickPlayControls(
              isPlaying: state.isPlaying,
              isBuffering: state.isBuffering || isLoading,
              onPlayPause: onPlayPause,
            ),

            const SizedBox(height: AppSpacing.xl),

            // Hint
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                '提示：快速播放不会创建工程，适合临时试听',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: AppSpacing.lg),
          ],
        );
      },
    );
  }
}

class _QuickPlayProgressBar extends StatelessWidget {
  final PlaybackState state;
  final ValueChanged<Duration> onSeek;

  const _QuickPlayProgressBar({
    required this.state,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final duration = state.duration;
    final max = duration?.inMilliseconds.toDouble() ?? 1.0;
    final value = state.position.inMilliseconds.toDouble().clamp(0.0, max);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.bgHighlight,
              thumbColor: AppColors.accent,
              overlayColor: AppColors.accent.withAlpha(26),
            ),
            child: Slider(
              value: value,
              min: 0,
              max: max,
              onChanged: duration != null
                  ? (v) => onSeek(Duration(milliseconds: v.toInt()))
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
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
          ),
        ],
      ),
    );
  }
}

class _QuickPlayControls extends StatelessWidget {
  final bool isPlaying;
  final bool isBuffering;
  final VoidCallback onPlayPause;

  const _QuickPlayControls({
    required this.isPlaying,
    required this.isBuffering,
    required this.onPlayPause,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
          ),
          child: isBuffering
              ? const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: AppColors.pureWhite,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : IconButton(
                  onPressed: onPlayPause,
                  icon: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                  ),
                  iconSize: 36,
                  color: AppColors.pureWhite,
                ),
        ),
      ],
    );
  }
}
