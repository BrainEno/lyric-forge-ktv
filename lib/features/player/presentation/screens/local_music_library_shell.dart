import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/transfer_entry.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_tap_pulse.dart';
import '../local_library_dependencies.dart';
import 'local_artist_album_browser_screen.dart';
import 'local_collections_screen.dart';
import 'local_library_explorer_screen.dart';

/// The music library, with its five sections.
///
/// This used to carry its own `NavigationRail` (with six destinations, one of
/// them 设置) and its own `NavigationBar` on narrow widths. Once the app grew a
/// persistent top-level navigation, those two stacked: a rail inside a rail on
/// desktop, a tab bar under a tab bar on mobile, and 设置 appeared twice.
///
/// The sections are a subset of one destination, so they are now a section
/// strip at the top of the library content and the app-level navigation owns the
/// vertical/horizontal edge. Nothing was removed: all five sections and the
/// transfer entry are still one press away.
class LocalMusicLibraryShell extends StatefulWidget {
  /// The 跨设备传输 button at the end of the section strip.
  static const transferButtonKey = ValueKey('library-transfer');

  final int initialIndex;

  /// Supplied by the routing table (`lib/app/local_library_assembly.dart`) and
  /// handed to each section. Builds only when [sections] is omitted.
  final LocalLibraryDependencies? dependencies;

  /// Section bodies. Injected by tests, which cannot stand up the library
  /// repositories; production builds them from [dependencies].
  final List<Widget>? sections;

  const LocalMusicLibraryShell({
    super.key,
    this.initialIndex = 0,
    this.dependencies,
    this.sections,
  }) : assert(
         dependencies != null || sections != null,
         'The shell needs either the library dependencies or explicit sections.',
       );

  @override
  State<LocalMusicLibraryShell> createState() => _LocalMusicLibraryShellState();
}

class _LocalMusicLibraryShellState extends State<LocalMusicLibraryShell> {
  late int _index;

  static const _sections = [
    _LibrarySection(
      label: '歌曲',
      icon: Icons.music_note_outlined,
      selectedIcon: Icons.music_note_rounded,
    ),
    _LibrarySection(
      label: '艺人',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
    _LibrarySection(
      label: '专辑',
      icon: Icons.album_outlined,
      selectedIcon: Icons.album_rounded,
    ),
    _LibrarySection(
      label: '收藏',
      icon: Icons.favorite_border_rounded,
      selectedIcon: Icons.favorite_rounded,
    ),
    _LibrarySection(
      label: '歌单',
      icon: Icons.queue_music_outlined,
      selectedIcon: Icons.queue_music_rounded,
    ),
  ];

  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, _sections.length - 1).toInt();
    _pages = _buildPages();
  }

  @override
  void didUpdateWidget(covariant LocalMusicLibraryShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _index = widget.initialIndex.clamp(0, _sections.length - 1).toInt();
    }
    if (!identical(oldWidget.sections, widget.sections) ||
        !identical(oldWidget.dependencies, widget.dependencies)) {
      _pages = _buildPages();
    }
  }

  /// Presses per section, for the chip icon pulse.
  final Map<int, int> _presses = {};

  void _openTransfer() => TransferEntry.open(context);

  /// A section press answers even when it is the open section: the chip icon
  /// pulses and the platform gives a selection click.
  void _select(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _presses[index] = (_presses[index] ?? 0) + 1;
      _index = index;
    });
  }

  /// Built once per dependency object: the sections live in an `IndexedStack`,
  /// so rebuilding them on every parent frame would throw away their scroll
  /// position and reload the library.
  List<Widget> _buildPages() {
    final sections = widget.sections;
    if (sections != null) return sections;
    final dependencies = widget.dependencies!;
    return [
      LocalLibraryExplorerScreen(dependencies: dependencies),
      LocalArtistAlbumBrowserScreen(
        view: LocalCatalogView.artists,
        dependencies: dependencies,
      ),
      LocalArtistAlbumBrowserScreen(
        view: LocalCatalogView.albums,
        dependencies: dependencies,
      ),
      LocalCollectionsScreen(
        view: LocalCollectionView.favorites,
        dependencies: dependencies,
      ),
      LocalCollectionsScreen(
        view: LocalCollectionView.playlists,
        dependencies: dependencies,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppResponsive.fromConstraints(constraints);
        final content = Column(
          children: [
            _SectionStrip(
              sections: _sections,
              selectedIndex: _index,
              presses: _presses,
              onSelected: _select,
              onOpenTransfer: _openTransfer,
            ),
            Expanded(
              child: _SectionSwitcher(index: _index, children: _pages),
            ),
          ],
        );

        if (!layout.isCompactOrMedium) {
          return ColoredBox(color: AppColors.bgBase, child: content);
        }
        // No floating button here: the 40 dp small FAB was under the 48 dp
        // target size and covered the last rows of every section (audit
        // L-01). The transfer button stays in the section strip instead.
        return Scaffold(backgroundColor: AppColors.bgBase, body: content);
      },
    );
  }
}

class _LibrarySection {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _LibrarySection({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

class _SectionStrip extends StatefulWidget {
  final List<_LibrarySection> sections;
  final int selectedIndex;
  final Map<int, int> presses;
  final ValueChanged<int> onSelected;
  final VoidCallback onOpenTransfer;

  const _SectionStrip({
    required this.sections,
    required this.selectedIndex,
    required this.presses,
    required this.onSelected,
    required this.onOpenTransfer,
  });

  @override
  State<_SectionStrip> createState() => _SectionStripState();
}

class _SectionStripState extends State<_SectionStrip> {
  late List<GlobalKey> _chipKeys = _keysFor(widget.sections.length);

  static List<GlobalKey> _keysFor(int count) =>
      List.generate(count, (_) => GlobalKey());

  @override
  void didUpdateWidget(covariant _SectionStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sections.length != widget.sections.length) {
      _chipKeys = _keysFor(widget.sections.length);
    }
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  /// On narrow windows the strip scrolls; bring the chosen chip into view so
  /// a section opened from elsewhere (收藏 from the player bar) is visible.
  void _revealSelected() {
    if (!mounted) return;
    final chip = _chipKeys[widget.selectedIndex].currentContext;
    if (chip == null) return;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    Scrollable.ensureVisible(
      chip,
      alignment: 0.5,
      duration: reduceMotion ? Duration.zero : _SectionSwitcher.duration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = widget.sections;
    final layout = AppResponsive.of(context);
    final gutter = layout.pageGutter.clamp(12, 24).toDouble();
    // Material, not Container: the section chips need a Material ancestor, and
    // the wide layout of this screen no longer sits inside a Scaffold.
    return Material(
      color: AppColors.bgElevated,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: gutter,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var index = 0; index < sections.length; index++) ...[
                      if (index > 0) const SizedBox(width: AppSpacing.xs),
                      ChoiceChip(
                        key: _chipKeys[index],
                        selected: index == widget.selectedIndex,
                        onSelected: (_) => widget.onSelected(index),
                        avatar: AppTapPulse(
                          trigger: widget.presses[index] ?? 0,
                          peakScale: 1.3,
                          child: Icon(
                            index == widget.selectedIndex
                                ? sections[index].selectedIcon
                                : sections[index].icon,
                            size: 16,
                          ),
                        ),
                        label: Text(sections[index].label),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filledTonal(
              key: LocalMusicLibraryShell.transferButtonKey,
              tooltip: TransferEntry.label,
              onPressed: widget.onOpenTransfer,
              style: IconButton.styleFrom(
                minimumSize: Size.square(layout.minimumInteractiveExtent),
              ),
              icon: const Icon(TransferEntry.icon),
            ),
          ],
        ),
      ),
    );
  }
}

/// The section bodies, kept alive in an [IndexedStack], with a short fade
/// and rise when the section changes.
///
/// Switching sections used to swap the body in a single frame, which on a
/// long list looked like the press had not registered, especially between
/// 收藏 and 歌单, whose lists look alike.
class _SectionSwitcher extends StatefulWidget {
  const _SectionSwitcher({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  static const Duration duration = Duration(milliseconds: 220);

  @override
  State<_SectionSwitcher> createState() => _SectionSwitcherState();
}

class _SectionSwitcherState extends State<_SectionSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _SectionSwitcher.duration,
    value: 1,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  static const Offset _start = Offset(0, 0.015);
  static final Animatable<double> _fade = Tween<double>(begin: 0.4, end: 1);
  static final Animatable<Offset> _up = Tween(begin: _start, end: Offset.zero);

  late final Animation<double> _opacity = _curve.drive(_fade);
  late final Animation<Offset> _offset = _curve.drive(_up);

  @override
  void didUpdateWidget(covariant _SectionSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: IndexedStack(index: widget.index, children: widget.children),
      ),
    );
  }
}
