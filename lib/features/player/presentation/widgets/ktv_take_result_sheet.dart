import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/audio_preview_state.dart';
import '../../domain/models/ktv_recording_session.dart';
import '../../domain/services/audio_preview_service.dart';
import '../../domain/services/ktv_recording_service.dart';
import '../recording_time_format.dart';
import 'ktv_control_label.dart';
import 'playback_error_banner.dart';

enum KtvTakePreviewKind { voice, mix }

/// Answers "does this recording still exist on disk?".
///
/// Injected so widget tests can decide the answer: real file I/O never
/// completes inside the fake-async zone `testWidgets` runs in.
typedef PreviewFileProbe = Future<bool> Function(String path);

Future<bool> _fileExists(String path) async =>
    await FileSystemEntity.type(path, followLinks: false) ==
    FileSystemEntityType.file;

/// Result sheet shown right after a KTV take finishes recording.
///
/// Owns no audio hardware: playback goes through the app-scoped
/// [AudioPreviewService], which pauses the song and refuses to sound while the
/// song plays. Before that split this widget built its own `just_audio`
/// player, so a take could play over the still-running song with no single
/// pause control.
class KtvTakeResultSheet extends StatefulWidget {
  final KtvRecordingSession initialSession;
  final KtvRecordingService recordingService;
  final AudioPreviewService previewService;

  /// Overrides the on-disk check; production always uses [_fileExists].
  final PreviewFileProbe? previewFileExists;

  const KtvTakeResultSheet({
    super.key,
    required this.initialSession,
    required this.recordingService,
    required this.previewService,
    this.previewFileExists,
  });

  @override
  State<KtvTakeResultSheet> createState() => _KtvTakeResultSheetState();
}

class _KtvTakeResultSheetState extends State<KtvTakeResultSheet> {
  late KtvRecordingSession _session;
  late double _voiceVolume;
  late double _backingVolume;
  bool _exporting = false;
  StreamSubscription<AudioPreviewState>? _previewSubscription;
  KtvTakePreviewKind _previewKind = KtvTakePreviewKind.voice;
  Duration _previewPosition = Duration.zero;
  Duration _previewDuration = Duration.zero;
  bool _previewLoaded = false;
  bool _previewPlaying = false;
  String? _error;

  bool get _hasMix => _session.mixedOutputPath != null;

  String? _previewPathFor(KtvTakePreviewKind kind) =>
      kind == KtvTakePreviewKind.mix
      ? _session.mixedOutputPath
      : _session.micStemPath;

  String _previewLabel(KtvTakePreviewKind kind) =>
      kind == KtvTakePreviewKind.mix ? '混音成品' : '原始人声';

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    _voiceVolume = 1.0;
    _backingVolume = _session.backingVolume;
    _previewKind = _hasMix ? KtvTakePreviewKind.mix : KtvTakePreviewKind.voice;
    _previewDuration = _session.duration;
    _previewSubscription = widget.previewService.stateStream.listen((preview) {
      if (!mounted) return;
      setState(() {
        _previewPosition = preview.position;
        final duration = preview.duration;
        if (duration != null) _previewDuration = duration;
        _previewPlaying = preview.isPlaying;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadPreview(_previewKind));
    });
  }

  Future<void> _loadPreview(
    KtvTakePreviewKind kind, {
    bool autoPlay = false,
  }) async {
    final previewPath = _previewPathFor(kind);
    final exists = widget.previewFileExists ?? _fileExists;
    if (previewPath == null || !await exists(previewPath)) {
      if (mounted) {
        setState(() {
          _previewLoaded = false;
          _previewPlaying = false;
          _error = '${_previewLabel(kind)}文件不存在或不可用';
        });
      }
      return;
    }
    try {
      final duration = await widget.previewService.loadFile(previewPath);
      if (!mounted) return;
      setState(() {
        _previewKind = kind;
        _previewLoaded = true;
        _previewPlaying = false;
        _previewPosition = Duration.zero;
        _previewDuration = duration ?? _session.duration;
        _error = null;
      });
      if (autoPlay) unawaited(widget.previewService.play());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _previewLoaded = false;
        _previewPlaying = false;
        _error = '加载${_previewLabel(kind)}失败：$error';
      });
    }
  }

  Future<void> _togglePreview() async {
    if (_exporting) return;
    if (!_previewLoaded) {
      await _loadPreview(_previewKind, autoPlay: true);
      return;
    }
    try {
      if (_previewPlaying) {
        await widget.previewService.pause();
        return;
      }
      if (_previewDuration > Duration.zero &&
          _previewPosition >= _previewDuration) {
        await widget.previewService.seek(Duration.zero);
      }
      unawaited(widget.previewService.play());
    } catch (error) {
      if (mounted) setState(() => _error = '试听失败：$error');
    }
  }

  Future<void> _seekPreview(double milliseconds) async {
    if (!_previewLoaded || _exporting) return;
    try {
      await widget.previewService.seek(
        Duration(milliseconds: milliseconds.round()),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '调整试听进度失败：$error');
    }
  }

  @override
  void dispose() {
    unawaited(_previewSubscription?.cancel() ?? Future.value());
    // The audition service outlives this sheet, so dismissing the sheet has to
    // stop the take explicitly; there is no player disposal to fall back on.
    unawaited(widget.previewService.stop());
    super.dispose();
  }

  Future<void> _exportMix() async {
    if (_exporting || !_session.alignmentReliable) return;
    if (_previewLoaded) {
      if (_previewKind == KtvTakePreviewKind.mix) {
        await _loadPreview(KtvTakePreviewKind.voice);
      } else {
        await widget.previewService.pause();
      }
    }
    if (!mounted) return;
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final exported = await widget.recordingService.exportMix(
        _session,
        voiceVolume: _voiceVolume,
        backingVolume: _backingVolume,
      );
      if (!mounted) return;
      setState(() {
        _session = exported;
        _exporting = false;
      });
      await _loadPreview(KtvTakePreviewKind.mix);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final maxPreviewMs = _previewDuration.inMilliseconds > 0
        ? _previewDuration.inMilliseconds
        : 1;
    final previewMs = _previewPosition.inMilliseconds
        .clamp(0, maxPreviewMs)
        .toDouble();
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        AppSpacing.sm,
        spec.pageGutter,
        AppSpacing.xxl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    _session.alignmentReliable
                        ? Icons.check_circle_rounded
                        : Icons.warning_amber_rounded,
                    color: _session.alignmentReliable
                        ? AppColors.accent
                        : AppColors.warning,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _session.displayName?.trim().isNotEmpty == true
                          ? _session.displayName!
                          : 'KTV 录音已保存',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '人声 stem（${formatRecordingTime(_session.duration)}）',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(
                _session.micStemPath,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              if (!_session.alignmentReliable) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _session.alignmentIssue ??
                      '播放时间轴在录音中发生变化，已保留人声 stem，但自动混音已禁用。',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.warning),
                ),
              ],
              if (_hasMix) ...[
                const SizedBox(height: AppSpacing.md),
                Text('混音成品', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                SelectableText(
                  _session.mixedOutputPath!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text(
                '试听版本',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  ChoiceChip(
                    label: const Text('原始人声'),
                    selected: _previewKind == KtvTakePreviewKind.voice,
                    onSelected: _exporting
                        ? null
                        : (selected) {
                            if (selected) {
                              unawaited(_loadPreview(KtvTakePreviewKind.voice));
                            }
                          },
                  ),
                  if (_hasMix)
                    ChoiceChip(
                      label: const Text('混音成品'),
                      selected: _previewKind == KtvTakePreviewKind.mix,
                      onSelected: _exporting
                          ? null
                          : (selected) {
                              if (selected) {
                                unawaited(_loadPreview(KtvTakePreviewKind.mix));
                              }
                            },
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Slider(
                value: previewMs,
                min: 0,
                max: maxPreviewMs.toDouble(),
                onChanged: !_previewLoaded || _exporting
                    ? null
                    : (value) => unawaited(_seekPreview(value)),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatRecordingTime(_previewPosition)),
                  Text(formatRecordingTime(_previewDuration)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _exporting ? null : _togglePreview,
                icon: Icon(
                  _previewPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                label: Text(
                  _previewPlaying
                      ? '暂停${_previewLabel(_previewKind)}'
                      : '播放${_previewLabel(_previewKind)}',
                ),
              ),
              if (!_hasMix) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '导出混音后，可在这里直接切换试听原始人声和混音成品。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              KtvControlLabel(
                title: '导出人声音量',
                value: '${(_voiceVolume * 100).round()}%',
              ),
              Slider(
                value: _voiceVolume,
                min: 0,
                max: 2,
                divisions: 20,
                onChanged: _exporting
                    ? null
                    : (value) => setState(() => _voiceVolume = value),
              ),
              KtvControlLabel(
                title: '导出伴奏音量',
                value: '${(_backingVolume * 100).round()}%',
              ),
              Slider(
                value: _backingVolume,
                min: 0,
                max: 1,
                divisions: 20,
                onChanged: _exporting
                    ? null
                    : (value) => setState(() => _backingVolume = value),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                PlaybackErrorBanner(message: _error!),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: !_session.alignmentReliable || _exporting
                    ? null
                    : _exportMix,
                icon: _exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.graphic_eq_rounded),
                label: Text(
                  _session.mixedOutputPath == null ? '导出 WAV 混音' : '重新导出混音',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
