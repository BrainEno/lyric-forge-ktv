import 'package:flutter/widgets.dart';

import 'app_appearance.dart';
import 'app_palette.dart';
import 'color_tokens.dart';

/// Puts the chosen theme into effect for everything below it.
///
/// Screens paint with `AppColors.*`, which reads one process-wide palette,
/// rather than with `Theme.of(context)`: about a thousand call sites, many of
/// them inside widgets that never look the theme up. So a theme change cannot
/// rely on inherited-widget dependencies alone. When the controller changes,
/// the host switches the palette and then marks every element below it for
/// rebuild — what a hot reload does — so each widget repaints with the new
/// tokens while keeping its state: the route stack, scroll positions, text
/// being typed and the song playing all survive the switch (decision D-042).
class AppAppearanceHost extends StatefulWidget {
  const AppAppearanceHost({
    super.key,
    required this.controller,
    required this.builder,
  });

  final AppAppearanceController controller;

  /// Builds the app for [variant], typically a `MaterialApp` whose theme is
  /// `AppTheme.themeFor(variant.palette)`.
  final Widget Function(BuildContext context, AppThemeVariant variant) builder;

  @override
  State<AppAppearanceHost> createState() => _AppAppearanceHostState();
}

class _AppAppearanceHostState extends State<AppAppearanceHost> {
  late AppThemeVariant _variant;

  @override
  void initState() {
    super.initState();
    _variant = widget.controller.variant;
    AppColors.usePalette(_variant.palette);
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant AppAppearanceHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      final next = widget.controller.variant;
      if (next != _variant) {
        _variant = next;
        AppColors.usePalette(next.palette);
        rebuildAllBelow(context);
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final next = widget.controller.variant;
    if (next == _variant) return;
    AppColors.usePalette(next.palette);
    setState(() => _variant = next);
    rebuildAllBelow(context);
  }

  /// Marks every element below [context] for rebuild.
  static void rebuildAllBelow(BuildContext context) {
    void mark(Element element) {
      element.markNeedsBuild();
      element.visitChildren(mark);
    }

    (context as Element).visitChildren(mark);
  }

  @override
  Widget build(BuildContext context) {
    return AppAppearanceScope(
      controller: widget.controller,
      child: widget.builder(context, _variant),
    );
  }
}

/// Hands the appearance controller to the widgets that switch themes — the
/// rail's theme button — without threading it through every constructor in
/// between.
class AppAppearanceScope extends InheritedNotifier<AppAppearanceController> {
  const AppAppearanceScope({
    super.key,
    required AppAppearanceController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The nearest controller, or null when the app was built without one
  /// (most widget tests).
  static AppAppearanceController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppAppearanceScope>()
        ?.notifier;
  }
}
