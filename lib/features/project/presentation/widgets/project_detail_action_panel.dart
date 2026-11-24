import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_button_spinner.dart';
import '../../../transcription/domain/models/spoken_language.dart';
import '../../domain/models/project_manifest.dart';
import 'project_audio_sources_section.dart';
import 'project_detail_cards.dart';
import 'project_sung_language_selector.dart';

/// 下一步: the button for what to do now, then recognition, the sung
/// language, the audio sources and the recognition settings (D-074).
class ProjectDetailActionPanel extends StatelessWidget {
  final ProjectManifest project;
  final bool isDesktop;
  final bool isTranscribing;
  final bool isImportingStem;
  final bool isImportingVocal;
  final bool audioSourcesExpanded;
  final ValueChanged<bool> onAudioSourcesExpandedChanged;
  final VoidCallback onImportAccompaniment;
  final VoidCallback onImportVocal;
  final AccompanimentGenerationView generation;
  final VoidCallback onTranscribe;
  final ValueChanged<String?>? onSungLanguageChanged;
  final VoidCallback onCancelTranscription;
  final VoidCallback onConfigureTranscription;
  final VoidCallback onOpenEditor;

  const ProjectDetailActionPanel({
    super.key,
    required this.project,
    required this.isDesktop,
    required this.isTranscribing,
    required this.isImportingStem,
    required this.isImportingVocal,
    required this.audioSourcesExpanded,
    required this.onAudioSourcesExpandedChanged,
    required this.onImportAccompaniment,
    required this.onImportVocal,
    required this.generation,
    required this.onTranscribe,
    required this.onSungLanguageChanged,
    required this.onCancelTranscription,
    required this.onConfigureTranscription,
    required this.onOpenEditor,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final buttonStyle = FilledButton.styleFrom(
      minimumSize: Size.fromHeight(spec.minimumInteractiveExtent),
    );
    final outlinedStyle = OutlinedButton.styleFrom(
      minimumSize: Size.fromHeight(spec.minimumInteractiveExtent),
    );

    return ProjectDetailSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '下一步',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            _nextStepText(project),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: AppSpacing.md),
          if (project.hasLyrics)
            FilledButton.icon(
              style: buttonStyle,
              onPressed: onOpenEditor,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('校对歌词'),
            )
          else if (isDesktop)
            FilledButton.icon(
              style: buttonStyle,
              onPressed:
                  isTranscribing ||
                      isImportingStem ||
                      generation.running ||
                      project.audioAsset == null
                  ? null
                  : onTranscribe,
              icon: isTranscribing
                  ? const AppButtonSpinner()
                  : const Icon(Icons.auto_awesome),
              label: Text(isTranscribing ? '正在生成歌词…' : '生成歌词'),
            )
          else
            const _DesktopRequiredNotice(),
          if (project.hasLyrics) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              style: outlinedStyle,
              onPressed: project.canPlay
                  ? () => Navigator.pushNamed(
                      context,
                      Routes.playerPath(project.id),
                    )
                  : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(project.canPlay ? '打开播放器' : '缺少工程音频'),
            ),
          ],
          if (isDesktop && project.hasLyrics && !isTranscribing) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: isImportingStem || generation.running
                  ? null
                  : onTranscribe,
              icon: const Icon(Icons.replay_rounded),
              label: const Text('重新识别歌词'),
            ),
          ],
          if (isTranscribing) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              style: outlinedStyle,
              onPressed: onCancelTranscription,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('取消识别'),
            ),
          ],
          if (isDesktop && project.audioAsset != null) ...[
            const SizedBox(height: AppSpacing.md),
            ProjectSungLanguageSelector(
              value: SpokenLanguageResolution.projectChoiceOf(project.metadata),
              recognizedAs: SpokenLanguageResolution.describeProject(
                project.metadata,
              ),
              onChanged: isTranscribing ? null : onSungLanguageChanged,
            ),
          ],
          if (isDesktop && project.audioAsset != null) ...[
            const Divider(height: AppSpacing.xl),
            ProjectAudioSourcesSection(
              audio: project.audioAsset!,
              expanded: audioSourcesExpanded,
              onExpandedChanged: onAudioSourcesExpandedChanged,
              busy: isTranscribing || isImportingStem,
              isImportingStem: isImportingStem,
              isImportingVocal: isImportingVocal,
              onImportAccompaniment: onImportAccompaniment,
              onImportVocal: onImportVocal,
              generation: generation,
            ),
          ],
          if (isDesktop) ...[
            const Divider(height: AppSpacing.xl),
            TextButton.icon(
              onPressed: isTranscribing ? null : onConfigureTranscription,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('识别环境与高级设置'),
            ),
          ],
        ],
      ),
    );
  }

  String _nextStepText(ProjectManifest project) {
    if (!project.hasLyrics) return '先生成歌词草稿，再进入逐行校对。';
    if (project.currentStage.index < ProcessingStage.lyricsEdited.index) {
      return '识别已经完成，建议先校对时间轴和文本。';
    }
    if (project.canPlay) return '歌词已经校对，可以进入播放器预览 KTV 效果。';
    return '歌词已准备好，工程需要音频才能进入播放器。';
  }
}

class _DesktopRequiredNotice extends StatelessWidget {
  const _DesktopRequiredNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.info.withAlpha(18),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: Text(
        '本地歌词自动识别需要在桌面端完成。',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}
