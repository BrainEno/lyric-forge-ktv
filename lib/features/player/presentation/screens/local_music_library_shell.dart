import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
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

  void _openTransfer() {
    Navigator.pushNamed(
      context,
      AppResponsive.isDesktopTarget()
          ? Routes.mediaSharing
          : Routes.remoteLibrary,
    );
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
              onSelected: (index) => setState(() => _index = index),
              onOpenTransfer: _openTransfer,
              showTransfer: !layout.isCompactOrMedium,
            ),
            Expanded(
              child: IndexedStack(index: _index, children: _pages),
            ),
          ],
        );

        if (!layout.isCompactOrMedium) {
          return ColoredBox(color: AppColors.bgBase, child: content);
        }
        return Scaffold(
          backgroundColor: AppColors.bgBase,
          body: content,
          floatingActionButton: FloatingActionButton.small(
            tooltip: '跨设备传输',
            onPressed: _openTransfer,
            child: const Icon(Icons.devices_rounded),
          ),
        );
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

class _SectionStrip extends StatelessWidget {
  final List<_LibrarySection> sections;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onOpenTransfer;
  final bool showTransfer;

  const _SectionStrip({
    required this.sections,
    required this.selectedIndex,
    required this.onSelected,
    required this.onOpenTransfer,
    required this.showTransfer,
  });

  @override
  Widget build(BuildContext context) {
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
                        selected: index == selectedIndex,
                        onSelected: (_) => onSelected(index),
                        avatar: Icon(
                          index == selectedIndex
                              ? sections[index].selectedIcon
                              : sections[index].icon,
                          size: 16,
                        ),
                        label: Text(sections[index].label),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (showTransfer) ...[
              const SizedBox(width: AppSpacing.sm),
              IconButton.filledTonal(
                tooltip: '跨设备传输',
                onPressed: onOpenTransfer,
                icon: const Icon(Icons.devices_rounded),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
