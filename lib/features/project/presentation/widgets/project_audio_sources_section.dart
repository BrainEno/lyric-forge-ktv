import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/audio_asset.dart';
import '../../domain/models/automatic_accompaniment.dart';

/// What the section shows about 自动生成伴奏 (D-060).
class AccompanimentGenerationView {
  /// Starts a generation; null hides the button (the platform cannot
  /// separate, or the project already has an accompaniment).
  final VoidCallback? onGenerate;

  /// A generation is running on this page.
  final bool running;

  /// The generation's own progress, 0 to 1.
  final double progress;

  /// What the generation is doing.
  final String message;
  final VoidCallback? onCancel;

  const AccompanimentGenerationView({
    this.onGenerate,
    this.running = false,
    this.progress = 0,
    this.message = '',
    this.onCancel,
  });

  static const AccompanimentGenerationView none = AccompanimentGenerationView();
}

/// 伴奏与人声: the two optional track imports of a project, folded behind one
/// row in the project's action panel.
///
/// Both imports used to sit in the panel as two full-width buttons right
/// below 校对歌词 and 打开播放器, so a rarely used audio-engineering step had
/// the same weight as the main path (audit P-02). The row now says which
/// tracks the project has and opens the buttons on demand. It stays open
/// while an import is running so its progress label remains visible.
class ProjectAudioSourcesSection extends StatelessWidget {
  const ProjectAudioSourcesSection({
    super.key,
    required this.audio,
    required this.expanded,
    required this.onExpandedChanged,
    required this.busy,
    required this.isImportingStem,
    required this.isImportingVocal,
    required this.onImportAccompaniment,
    required this.onImportVocal,
    this.generation = AccompanimentGenerationView.none,
  });

  final AudioAsset audio;

  /// Whether the user opened the section.
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  /// Another operation (recognition or an import) is running.
  final bool busy;
  final bool isImportingStem;
  final bool isImportingVocal;
  final VoidCallback onImportAccompaniment;
  final VoidCallback onImportVocal;
  final AccompanimentGenerationView generation;

  static const Key toggleKey = ValueKey('project-detail:audio-sources');
  static const Key generateKey = ValueKey('project-detail:generate-backing');
  static const Key cancelGenerationKey = ValueKey(
    'project-detail:cancel-backing',
  );

  /// Whether the buttons are shown: opened by the user, or an import or a
  /// generation is running.
  bool get showsActions => expanded || isImportingStem || generation.running;

  /// Accompaniment label: import, replace, or the running import.
  String get accompanimentLabel {
    if (isImportingStem && !isImportingVocal) return '正在导入伴奏…';
    if (audio.hasAutomaticAccompaniment) return '换成已有伴奏';
    return audio.instrumentalPath == null ? '导入已有伴奏' : '更换伴奏';
  }

  /// Vocal label: import, replace, or the running import.
  String get vocalLabel {
    if (isImportingStem && isImportingVocal) return '正在导入人声…';
    return audio.vocalPath == null ? '导入已有人声' : '更换人声';
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final text = Theme.of(context).textTheme;
    final outlinedStyle = OutlinedButton.styleFrom(
      minimumSize: Size.fromHeight(spec.minimumInteractiveExtent),
    );
    final open = showsActions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: open,
          child: InkWell(
            key: toggleKey,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            onTap: isImportingStem || generation.running
                ? null
                : () => onExpandedChanged(!expanded),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: spec.minimumInteractiveExtent,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    Icon(
                      Icons.graphic_eq_rounded,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '伴奏与人声',
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            audioSourcesSummary(audio),
                            style: text.bodySmall?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ExcludeSemantics(
                      child: AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(
                          Icons.expand_more_rounded,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (open) ...[
          if (generation.running) ...[
            const SizedBox(height: AppSpacing.sm),
            _GenerationProgress(generation: generation),
          ] else if (generation.onGenerate != null) ...[
            const SizedBox(height: AppSpacing.sm),
            FilledButton.tonalIcon(
              key: generateKey,
              style: FilledButton.styleFrom(
                minimumSize: Size.fromHeight(spec.minimumInteractiveExtent),
              ),
              onPressed: busy ? null : generation.onGenerate,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('自动生成伴奏'),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            style: outlinedStyle,
            onPressed: busy || generation.running
                ? null
                : onImportAccompaniment,
            icon: const Icon(Icons.library_music_outlined),
            label: Text(accompanimentLabel),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            style: outlinedStyle,
            onPressed: busy || generation.running ? null : onImportVocal,
            icon: const Icon(Icons.mic_none_rounded),
            label: Text(vocalLabel),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '选择与原曲时间轴一致的人声或伴奏；应用不会校准时间轴。'
            'Windows 版识别歌词前会自动分离人声并顺带生成伴奏，'
            '也可以直接自动生成伴奏；导入的人声优先，导入的伴奏不会被替换。',
            style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ],
    );
  }
}

/// One line about which optional tracks a project has, e.g.
/// 已有伴奏轨 · 没有人声轨. Worded apart from the 伴奏已导入 SnackBar.
String audioSourcesSummary(AudioAsset audio) {
  final hasAccompaniment = audio.instrumentalPath != null;
  final hasVocal = audio.vocalPath != null;
  if (!hasAccompaniment && !hasVocal) return '可选：导入与原曲对齐的伴奏或人声';
  final accompaniment = audio.hasAutomaticAccompaniment
      ? '已有伴奏轨（自动分离）'
      : hasAccompaniment
      ? '已有伴奏轨'
      : '没有伴奏轨';
  final vocal = hasVocal ? '已有人声轨' : '没有人声轨';
  return '$accompaniment · $vocal';
}

/// The running 自动生成伴奏: what it is doing, how far, and a way to stop.
class _GenerationProgress extends StatelessWidget {
  const _GenerationProgress({required this.generation});

  final AccompanimentGenerationView generation;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final fraction = generation.progress.clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                generation.message.isEmpty ? '正在生成伴奏…' : generation.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${(fraction * 100).round()}%',
              style: text.labelLarge?.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          child: LinearProgressIndicator(
            value: fraction <= 0 ? null : fraction,
            minHeight: 6,
            color: AppColors.accent,
            backgroundColor: AppColors.bgSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '首次使用要下载约 200 MB 的分离组件；用显卡一般一到三分钟，只用 CPU 会更久。',
          style: text.bodySmall?.copyWith(color: AppColors.textTertiary),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            key: ProjectAudioSourcesSection.cancelGenerationKey,
            onPressed: generation.onCancel,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('停止生成'),
          ),
        ),
      ],
    );
  }
}
