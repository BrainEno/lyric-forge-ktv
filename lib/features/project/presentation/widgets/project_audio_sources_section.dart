import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/audio_asset.dart';

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

  static const Key toggleKey = ValueKey('project-detail:audio-sources');

  /// Whether the buttons are shown: opened by the user, or an import is
  /// running.
  bool get showsActions => expanded || isImportingStem;

  /// Accompaniment label: import, replace, or the running import.
  String get accompanimentLabel {
    if (isImportingStem && !isImportingVocal) return '正在导入伴奏…';
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
            onTap: isImportingStem ? null : () => onExpandedChanged(!expanded),
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
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            style: outlinedStyle,
            onPressed: busy ? null : onImportAccompaniment,
            icon: const Icon(Icons.library_music_outlined),
            label: Text(accompanimentLabel),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            style: outlinedStyle,
            onPressed: busy ? null : onImportVocal,
            icon: const Icon(Icons.mic_none_rounded),
            label: Text(vocalLabel),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '选择与原曲时间轴一致的人声或伴奏；应用不会自动分离或校准。',
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
  final accompaniment = hasAccompaniment ? '已有伴奏轨' : '没有伴奏轨';
  final vocal = hasVocal ? '已有人声轨' : '没有人声轨';
  return '$accompaniment · $vocal';
}
