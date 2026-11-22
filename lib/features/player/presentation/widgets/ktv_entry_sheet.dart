import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/ktv_backing_mode.dart';

/// A choice and the exact source path displayed when the user selected it.
class KtvEntrySelection {
  final KtvBackingMode mode;
  final String sourcePath;

  const KtvEntrySelection({required this.mode, required this.sourcePath});
}

class KtvEntrySheet extends StatelessWidget {
  final AudioAsset audioAsset;
  final AudioSourceType? currentSource;
  final bool sessionMatches;

  const KtvEntrySheet({
    super.key,
    required this.audioAsset,
    required this.currentSource,
    this.sessionMatches = true,
  });

  @override
  Widget build(BuildContext context) {
    final instrumentalAvailable = audioAsset.hasSource(
      AudioSourceType.instrumental,
    );
    void select(KtvBackingMode mode) {
      final path = audioAsset.getPathForSource(mode.source);
      if (path == null) return;
      Navigator.pop(context, KtvEntrySelection(mode: mode, sourcePath: path));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mic_rounded, color: AppColors.accent),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '进入 KTV',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '选择演唱时保留原唱伴唱，或只播放纯伴奏。切换音轨会保留当前播放位置。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          _KtvModeTile(
            mode: KtvBackingMode.guideVocal,
            description: KtvBackingMode.guideVocal.descriptionFor(audioAsset),
            selected: currentSource == KtvBackingMode.guideVocal.source,
            enabled: sessionMatches,
            onSelected: select,
          ),
          const SizedBox(height: AppSpacing.sm),
          _KtvModeTile(
            mode: KtvBackingMode.instrumental,
            description: KtvBackingMode.instrumental.descriptionFor(audioAsset),
            selected: currentSource == KtvBackingMode.instrumental.source,
            enabled: sessionMatches && instrumentalAvailable,
            onSelected: select,
          ),
          if (!sessionMatches) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '当前播放项已变化，请关闭后重新打开 KTV。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ] else if (!instrumentalAvailable) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              ktvInstrumentalUnavailableHint,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Why 纯伴奏 is greyed out and how to get one (D-060).
const String ktvInstrumentalUnavailableHint =
    '纯伴奏暂不可用：可在电脑端工程详情的“伴奏与人声”里导入已有伴奏；'
    'Windows 版还可以自动生成伴奏，识别歌词时也会顺带生成。';

class _KtvModeTile extends StatelessWidget {
  final KtvBackingMode mode;
  final String description;
  final bool selected;
  final bool enabled;
  final ValueChanged<KtvBackingMode> onSelected;

  const _KtvModeTile({
    required this.mode,
    required this.description,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent.withAlpha(18) : AppColors.bgSurface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      child: ListTile(
        enabled: enabled,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        ),
        leading: Icon(
          mode == KtvBackingMode.guideVocal
              ? Icons.record_voice_over_rounded
              : Icons.music_note_rounded,
          color: enabled ? AppColors.accent : AppColors.textTertiary,
        ),
        title: Text(
          mode.label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(description),
        trailing: selected ? const Icon(Icons.check_circle_rounded) : null,
        onTap: enabled ? () => onSelected(mode) : null,
      ),
    );
  }
}
