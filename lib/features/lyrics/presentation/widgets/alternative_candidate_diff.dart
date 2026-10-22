import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/services/character_diff_service.dart';

/// Side-by-side textual evidence for a second-engine lyric candidate.
class AlternativeCandidateDiff extends StatelessWidget {
  static const _diffService = CharacterDiffService();

  final String currentText;
  final String alternativeText;

  const AlternativeCandidateDiff({
    super.key,
    required this.currentText,
    required this.alternativeText,
  });

  Widget _line(
    BuildContext context, {
    required String label,
    required bool showAlternative,
    required List<CharacterDiffSegment> segments,
  }) {
    final spans = <TextSpan>[];
    for (final segment in segments) {
      if (showAlternative && segment.type == CharacterDiffType.delete) {
        continue;
      }
      if (!showAlternative && segment.type == CharacterDiffType.insert) {
        continue;
      }
      final changed = segment.type != CharacterDiffType.equal;
      final color = showAlternative ? AppColors.accent : AppColors.error;
      spans.add(
        TextSpan(
          text: segment.text,
          style: changed
              ? TextStyle(
                  color: color,
                  backgroundColor: color.withAlpha(28),
                  fontWeight: FontWeight.w700,
                  decoration: showAlternative
                      ? null
                      : TextDecoration.lineThrough,
                  decorationColor: AppColors.error,
                )
              : null,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 64,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(children: spans),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final segments = _diffService.diff(currentText, alternativeText);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _line(
          context,
          label: '主引擎结果',
          showAlternative: false,
          segments: segments,
        ),
        const SizedBox(height: AppSpacing.xs),
        _line(
          context,
          label: '备选引擎结果',
          showAlternative: true,
          segments: segments,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '红色删除线标出主引擎中不同的字符；强调色标出备选引擎对应的字符。',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}
