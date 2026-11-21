import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/services/asr_managed_storage_service.dart';
import '../asr_leftover_text.dart';

/// Lists the leftover copies of the speech recognition environment and
/// offers to merge and remove them (D-048).
///
/// Shown in 设置 → 本地识别 → 模型与存储 whenever [AsrManagedStorageLocation]
/// reports a leftover, and while the message of the last clean-up is still
/// worth reading.
class AsrLeftoverNotice extends StatelessWidget {
  const AsrLeftoverNotice({
    super.key,
    required this.location,
    required this.cleaning,
    required this.onCleanUp,
    this.message,
  });

  /// The last inspection; its leftovers are listed.
  final AsrManagedStorageLocation? location;

  /// A clean-up is running.
  final bool cleaning;

  /// What the last clean-up did, or why it failed.
  final String? message;

  /// Null while another flow is running.
  final VoidCallback? onCleanUp;

  /// Whether the notice has anything to show for [location] and [message].
  static bool showsFor(AsrManagedStorageLocation? location, String? message) =>
      (location?.leftovers.isNotEmpty ?? false) || message != null;

  @override
  Widget build(BuildContext context) {
    final leftovers = location?.leftovers ?? const <AsrRuntimeLeftover>[];
    final textTheme = Theme.of(context).textTheme;
    final bodyStyle = textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
      height: 1.45,
    );
    return Container(
      key: const ValueKey('asr_leftover_notice'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(14),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.warning.withAlpha(72)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cleaning_services_rounded,
                size: 20,
                color: AppColors.warning,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  leftovers.isEmpty
                      ? '重复的识别环境'
                      : AsrLeftoverText.title(location!),
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          for (final leftover in leftovers) ...[
            const SizedBox(height: AppSpacing.sm),
            SelectableText(AsrLeftoverText.line(leftover), style: bodyStyle),
          ],
          if (message != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SelectableText(
              message!,
              key: const ValueKey('asr_leftover_message'),
              style: bodyStyle,
            ),
          ],
          if (leftovers.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                key: const ValueKey('asr_leftover_clean_up'),
                onPressed: cleaning ? null : onCleanUp,
                icon: cleaning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.merge_type_rounded, size: 18),
                label: Text(
                  cleaning
                      ? AsrLeftoverText.cleaningLabel
                      : AsrLeftoverText.cleanUpLabel,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Asks before the leftovers of [location] are merged and removed.
Future<bool> confirmAsrLeftoverCleanup(
  BuildContext context,
  AsrManagedStorageLocation location,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(AsrLeftoverText.confirmTitle),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: SelectableText(AsrLeftoverText.confirmation(location)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('asr_leftover_confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text(AsrLeftoverText.confirmAction),
        ),
      ],
    ),
  );
  return confirmed == true;
}
