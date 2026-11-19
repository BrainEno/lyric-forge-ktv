import 'package:flutter/material.dart';

import '../../../../core/theme/spacing_tokens.dart';

/// Places the two settings groups side by side when there is room.
///
/// On a 1920 px window the settings page used to be one 1400 px column of
/// cards, with the runtime controls stretched across the screen and the
/// troubleshooting cards far below the fold (audit SE-06). From
/// [twoColumnMinWidth] of content width the recognition settings take the
/// wider left column and troubleshooting the right; narrower windows keep a
/// single column, recognition first.
///
/// Both groups keep their state when a window resize crosses the breakpoint,
/// so a runtime check in progress is not restarted.
class SettingsColumns extends StatefulWidget {
  const SettingsColumns({
    super.key,
    required this.primary,
    required this.secondary,
  });

  /// The main group: the left column, or the top of the single column.
  final Widget primary;

  /// The supporting group: the right column, or below [primary].
  final Widget secondary;

  /// Content width from which the groups sit side by side.
  static const double twoColumnMinWidth = 1080;

  /// Space between the columns, or between the stacked groups.
  static const double gap = AppSpacing.xl;

  /// Flex of the primary and secondary columns.
  static const int primaryFlex = 3;
  static const int secondaryFlex = 2;

  static bool useTwoColumns(double width) => width >= twoColumnMinWidth;

  @override
  State<SettingsColumns> createState() => _SettingsColumnsState();
}

class _SettingsColumnsState extends State<SettingsColumns> {
  final _primaryKey = GlobalKey(debugLabel: 'settings-columns:primary');
  final _secondaryKey = GlobalKey(debugLabel: 'settings-columns:secondary');

  @override
  Widget build(BuildContext context) {
    final primary = KeyedSubtree(key: _primaryKey, child: widget.primary);
    final secondary = KeyedSubtree(key: _secondaryKey, child: widget.secondary);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!SettingsColumns.useTwoColumns(constraints.maxWidth)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              const SizedBox(height: SettingsColumns.gap),
              secondary,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: SettingsColumns.primaryFlex, child: primary),
            const SizedBox(width: SettingsColumns.gap),
            Expanded(flex: SettingsColumns.secondaryFlex, child: secondary),
          ],
        );
      },
    );
  }
}
