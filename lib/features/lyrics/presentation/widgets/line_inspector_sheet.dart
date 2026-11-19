import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';

/// Heights of the narrow-screen line inspector sheet, as fractions of the
/// space above the keyboard.
class LineInspectorSheetSizes {
  const LineInspectorSheetSizes({
    required this.initial,
    required this.min,
    required this.max,
  });

  final double initial;
  final double min;
  final double max;

  /// Resting points the sheet snaps to between [min] and [max].
  List<double> get snapSizes => [if (initial > min && initial < max) initial];
}

/// Bottom sheet that hosts the line inspector on narrow layouts.
///
/// The sheet used to open at a fixed 88 % of the screen (96 % on short
/// screens), hiding the lyric list the user was reviewing (audit E-05). It now
/// opens at about 60 %, shows the lines before and after the selected one,
/// and can be dragged by its handle, or by the inspector when it is scrolled
/// to the top, up to the full inspector or down to see more of the list. It
/// opens tall when the text field is focused on open (a new line), so the
/// field is not pushed under the keyboard, and on short screens, where 60 %
/// would leave too little room to edit.
class LineInspectorSheet extends StatefulWidget {
  const LineInspectorSheet({
    super.key,
    required this.editingText,
    required this.inspectorBuilder,
    this.previousLine,
    this.nextLine,
  });

  /// The inspector focuses its text field on open.
  final bool editingText;

  /// Builds the inspector; pass the controller to its scroll view so the
  /// sheet drags when the inspector is scrolled to the top.
  final Widget Function(ScrollController controller) inspectorBuilder;

  /// Text of the neighbouring lines, shown above the inspector for context.
  final String? previousLine;
  final String? nextLine;

  static const Key handleKey = ValueKey('line-inspector-sheet:handle');
  static const Key closeKey = ValueKey('line-inspector-sheet:close');
  static const Key contextKey = ValueKey('line-inspector-sheet:context');

  /// Sheet heights for [layout].
  static LineInspectorSheetSizes sizesFor(
    AppLayoutSpec layout, {
    required bool editingText,
  }) {
    if (layout.isShort) {
      return const LineInspectorSheetSizes(initial: 0.96, min: 0.5, max: 0.96);
    }
    if (editingText) {
      return const LineInspectorSheetSizes(initial: 0.92, min: 0.4, max: 0.92);
    }
    return const LineInspectorSheetSizes(initial: 0.62, min: 0.4, max: 0.92);
  }

  /// The resting size closest to [size], for a drag that ends at [size].
  ///
  /// A fling faster than [flingVelocity] logical pixels per second (positive
  /// is downwards) moves to the next resting size in that direction instead.
  static double settleSize(
    LineInspectorSheetSizes sizes,
    double size, {
    double velocity = 0,
  }) {
    final stops = {sizes.min, ...sizes.snapSizes, sizes.max}.toList()..sort();
    if (velocity.abs() >= flingVelocity) {
      if (velocity < 0) {
        return stops.firstWhere(
          (stop) => stop > size,
          orElse: () => stops.last,
        );
      }
      return stops.lastWhere((stop) => stop < size, orElse: () => stops.first);
    }
    var best = stops.first;
    for (final stop in stops) {
      if ((stop - size).abs() < (best - size).abs()) best = stop;
    }
    return best;
  }

  static const double flingVelocity = 700;

  @override
  State<LineInspectorSheet> createState() => _LineInspectorSheetState();
}

class _LineInspectorSheetState extends State<LineInspectorSheet> {
  final _controller = DraggableScrollableController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dragBy(double delta, double extent, LineInspectorSheetSizes sizes) {
    if (!_controller.isAttached || extent <= 0) return;
    final next = _controller.size - delta / extent;
    _controller.jumpTo(next.clamp(sizes.min, sizes.max));
  }

  void _settle(double velocity, LineInspectorSheetSizes sizes) {
    if (!_controller.isAttached) return;
    final target = LineInspectorSheet.settleSize(
      sizes,
      _controller.size,
      velocity: velocity,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sizes = LineInspectorSheet.sizesFor(
      AppResponsive.of(context),
      editingText: widget.editingText,
    );
    final before = _clean(widget.previousLine);
    final after = _clean(widget.nextLine);

    return Padding(
      // Keeps the sheet, and the focused text field, above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: LayoutBuilder(
        builder: (context, constraints) => DraggableScrollableSheet(
          controller: _controller,
          expand: false,
          initialChildSize: sizes.initial,
          minChildSize: sizes.min,
          maxChildSize: sizes.max,
          snap: true,
          snapSizes: sizes.snapSizes,
          // Resting at the smallest size keeps the sheet open; the modal
          // would otherwise close it there. It closes from the 关闭 button,
          // the barrier or back.
          shouldCloseOnMinExtent: false,
          builder: (context, controller) => Column(
            children: [
              _SheetHeader(
                onDragUpdate: (delta) =>
                    _dragBy(delta, constraints.maxHeight, sizes),
                onDragEnd: (velocity) => _settle(velocity, sizes),
              ),
              if (before != null || after != null)
                _NeighbourLines(previous: before, next: after),
              Expanded(child: widget.inspectorBuilder(controller)),
            ],
          ),
        ),
      ),
    );
  }

  static String? _clean(String? text) {
    final value = text?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}

/// Drag handle with a close button; dragging anywhere on it resizes the
/// sheet.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.onDragUpdate, required this.onDragEnd});

  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: LineInspectorSheet.handleKey,
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) => onDragUpdate(details.delta.dy),
      onVerticalDragEnd: (details) =>
          onDragEnd(details.velocity.pixelsPerSecond.dy),
      child: SizedBox(
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.pressedOverlay,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                ),
              ),
            ),
            Positioned(
              right: AppSpacing.xs,
              child: IconButton(
                key: LineInspectorSheet.closeKey,
                tooltip: '关闭',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 上一行 / 下一行 above the inspector, one line each.
class _NeighbourLines extends StatelessWidget {
  const _NeighbourLines({required this.previous, required this.next});

  final String? previous;
  final String? next;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = text.bodySmall?.copyWith(color: AppColors.textTertiary);
    final before = previous;
    final after = next;

    Widget row(String label, String line) => Text(
      '$label：$line',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );

    return Padding(
      key: LineInspectorSheet.contextKey,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (before != null) row('上一行', before),
          if (after != null) row('下一行', after),
        ],
      ),
    );
  }
}
