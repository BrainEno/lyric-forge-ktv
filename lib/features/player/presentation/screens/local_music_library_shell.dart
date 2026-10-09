import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/theme/color_tokens.dart';
import 'local_artist_album_browser_screen.dart';
import 'local_collections_screen.dart';
import 'local_library_explorer_screen.dart';

class LocalMusicLibraryShell extends StatefulWidget {
  final int initialIndex;

  const LocalMusicLibraryShell({
    super.key,
    this.initialIndex = 0,
  });

  @override
  State<LocalMusicLibraryShell> createState() => _LocalMusicLibraryShellState();
}

class _LocalMusicLibraryShellState extends State<LocalMusicLibraryShell> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, 4).toInt();
  }

  @override
  void didUpdateWidget(covariant LocalMusicLibraryShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _index = widget.initialIndex.clamp(0, 4).toInt();
    }
  }

  void _openTransfer(BuildContext context) {
    Navigator.pushNamed(
      context,
      AppResponsive.isDesktopTarget()
          ? Routes.mediaSharing
          : Routes.remoteLibrary,
    );
  }

  void _selectDesktopDestination(BuildContext context, int value) {
    if (value == 5) {
      Navigator.pushNamed(context, Routes.settings);
      return;
    }
    setState(() => _index = value);
  }

  List<Widget> get _pages => const [
        LocalLibraryExplorerScreen(),
        LocalArtistAlbumBrowserScreen(view: LocalCatalogView.artists),
        LocalArtistAlbumBrowserScreen(view: LocalCatalogView.albums),
        LocalCollectionsScreen(view: LocalCollectionView.favorites),
        LocalCollectionsScreen(view: LocalCollectionView.playlists),
      ];

  static const _railDestinations = [
    NavigationRailDestination(
      icon: Icon(Icons.music_note_outlined),
      selectedIcon: Icon(Icons.music_note_rounded),
      label: Text('歌曲'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.person_outline_rounded),
      selectedIcon: Icon(Icons.person_rounded),
      label: Text('艺人'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.album_outlined),
      selectedIcon: Icon(Icons.album_rounded),
      label: Text('专辑'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.favorite_border_rounded),
      selectedIcon: Icon(Icons.favorite_rounded),
      label: Text('已收藏'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.queue_music_outlined),
      selectedIcon: Icon(Icons.queue_music_rounded),
      label: Text('播放列表'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: Text('设置'),
    ),
  ];

  static const _bottomDestinations = [
    NavigationDestination(
      icon: Icon(Icons.music_note_outlined),
      selectedIcon: Icon(Icons.music_note_rounded),
      label: '歌曲',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline_rounded),
      selectedIcon: Icon(Icons.person_rounded),
      label: '艺人',
    ),
    NavigationDestination(
      icon: Icon(Icons.album_outlined),
      selectedIcon: Icon(Icons.album_rounded),
      label: '专辑',
    ),
    NavigationDestination(
      icon: Icon(Icons.favorite_border_rounded),
      selectedIcon: Icon(Icons.favorite_rounded),
      label: '收藏',
    ),
    NavigationDestination(
      icon: Icon(Icons.queue_music_outlined),
      selectedIcon: Icon(Icons.queue_music_rounded),
      label: '歌单',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppResponsive.fromConstraints(constraints);

        if (layout.useNavigationRail) {
          return ColoredBox(
            color: AppColors.bgBase,
            child: Row(
              children: [
                NavigationRail(
                  backgroundColor: AppColors.bgElevated,
                  selectedIndex: _index,
                  labelType: NavigationRailLabelType.all,
                  minWidth: 76,
                  groupAlignment: -0.72,
                  onDestinationSelected: (value) =>
                      _selectDesktopDestination(context, value),
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.library_music_rounded, size: 30),
                        const SizedBox(height: 12),
                        IconButton.filledTonal(
                          tooltip: '跨设备传输',
                          onPressed: () => _openTransfer(context),
                          icon: const Icon(Icons.devices_rounded),
                        ),
                      ],
                    ),
                  ),
                  destinations: _railDestinations,
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: IndexedStack(
                    index: _index,
                    children: _pages,
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.bgBase,
          body: IndexedStack(
            index: _index,
            children: _pages,
          ),
          floatingActionButton: FloatingActionButton.small(
            tooltip: '跨设备传输',
            onPressed: () => _openTransfer(context),
            child: const Icon(Icons.devices_rounded),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            labelBehavior: layout.isCompact
                ? NavigationDestinationLabelBehavior.onlyShowSelected
                : NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: _bottomDestinations,
          ),
        );
      },
    );
  }
}
