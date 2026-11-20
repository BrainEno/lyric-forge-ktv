import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// A card, row or tile that a tap opens or plays, as a screen reader meets
/// it: one button with a spoken label (audit A-04).
///
/// Cards built from a bare `InkWell` used to be read as whatever text they
/// held — the title, a `·`, a count — with no hint that a tap does
/// anything, which state the colour or a dot was showing, or that a card
/// was disabled. Buttons nested inside the card (a ⋯ menu, a remove button)
/// were separate stops whose purpose depended on the card before them.
///
/// [AppTapTarget] reads the whole card as [label] with [hint] (what a tap
/// does), keeps [selected] and the disabled state, and exposes the nested
/// buttons as [actions] so they stay reachable from the screen reader's
/// actions menu. The child is excluded from semantics, so the pieces are not
/// read a second time; pointer and keyboard use of the child is unchanged.
class AppTapTarget extends StatelessWidget {
  const AppTapTarget({
    super.key,
    required this.label,
    this.hint,
    this.value,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.selected,
    this.actions = const {},
    this.container = true,
    required this.child,
  });

  /// What the card is, in one sentence; see [AppTapTarget.join].
  final String label;

  /// What a tap does, e.g. 播放 or 打开专辑.
  final String? hint;

  /// A changing value such as a progress percentage.
  final String? value;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// False reads the card as disabled and drops its tap and hint. The
  /// [actions] stay: an unavailable song can still be relinked or removed.
  final bool enabled;

  /// Non-null for cards that can be the current one (the playing song, the
  /// open lyric line); null for cards without that state.
  final bool? selected;

  /// The nested buttons by label, in reading order. A null callback leaves
  /// the action out, e.g. a menu entry that is unavailable right now.
  final Map<String, VoidCallback?> actions;

  /// False lets the label join an enclosing node instead of starting its
  /// own, e.g. a reorderable row whose list adds 上移/下移 actions on the
  /// row's wrapper. Leave [actions] empty then: two sets of custom actions
  /// would split the row into two nodes again.
  final bool container;
  final Widget child;

  /// Joins the parts of a label with the Chinese comma, skipping empty ones,
  /// e.g. `['晴天', null, ' 周杰伦 ']` → `晴天，周杰伦`.
  static String join(Iterable<String?> parts) {
    return parts
        .map((part) => part?.trim() ?? '')
        .where((part) => part.isNotEmpty)
        .join('，');
  }

  /// [actions] as custom semantics actions, in order, without the null ones.
  static Map<CustomSemanticsAction, VoidCallback> actionsFor(
    Map<String, VoidCallback?> actions,
  ) {
    return {
      for (final entry in actions.entries)
        CustomSemanticsAction(label: entry.key): ?entry.value,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tap = enabled ? onTap : null;
    // An empty map still marks the node as having custom actions, which
    // would keep a `container: false` label from joining its parent.
    final customActions = actionsFor(actions);
    return Semantics(
      container: container,
      excludeSemantics: true,
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      value: value,
      hint: enabled ? hint : null,
      onTap: tap,
      onLongPress: enabled ? onLongPress : null,
      customSemanticsActions: customActions.isEmpty ? null : customActions,
      child: child,
    );
  }
}
