import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../transcription/domain/models/spoken_language.dart';

/// 演唱语言 of one song on its project page (D-062).
///
/// 自动判断 (null) leaves the language to the recognition settings and the
/// probe of the sung parts (D-061). A language set here wins over both, and
/// the editor's re-recognition of a stretch uses it too: the fix for a song
/// the probe gets wrong, without changing the settings of every other song.
class ProjectSungLanguageSelector extends StatelessWidget {
  const ProjectSungLanguageSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.recognizedAs,
  });

  /// The language set for this song, or null for 自动判断.
  final String? value;

  /// Null disables the selector (while recognition runs).
  final ValueChanged<String?>? onChanged;

  /// What the last recognition used, e.g. `英文（自动判断）`, shown under the
  /// selector while it is on 自动判断.
  final String? recognizedAs;

  static const String autoLabel = '自动判断';

  /// The entries in menu order: 自动判断, the offered languages, and a
  /// language set before the list changed.
  static List<String?> options(String? value) => [
    null,
    ...SpokenLanguagePolicy.selectableLanguages,
    if (value != null &&
        !SpokenLanguagePolicy.selectableLanguages.contains(value))
      value,
  ];

  static String labelOf(String? code) =>
      code == null ? autoLabel : SpokenLanguagePolicy.label(code);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = value == null
        ? (recognizedAs == null ? '识别时先听演唱部分再定语言' : '上次识别：$recognizedAs')
        : '这首歌固定按${labelOf(value)}识别，不受识别设置影响';
    return Column(
      key: const ValueKey('project_sung_language'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              Icons.translate_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text('演唱语言', style: theme.textTheme.bodyMedium),
            const Spacer(),
            PopupMenuButton<String>(
              key: const ValueKey('project_sung_language_menu'),
              enabled: onChanged != null,
              tooltip: '设置这首歌的演唱语言',
              initialValue: value ?? SpokenLanguagePolicy.auto,
              onSelected: (selected) => onChanged?.call(
                selected == SpokenLanguagePolicy.auto ? null : selected,
              ),
              itemBuilder: (context) => [
                for (final code in options(value))
                  PopupMenuItem<String>(
                    key: ValueKey(
                      'project_sung_language_${code ?? SpokenLanguagePolicy.auto}',
                    ),
                    value: code ?? SpokenLanguagePolicy.auto,
                    child: Text(labelOf(code)),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      labelOf(value),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: onChanged == null
                            ? AppColors.textTertiary
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Text(
          hint,
          key: const ValueKey('project_sung_language_hint'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}
