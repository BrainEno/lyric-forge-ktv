import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import 'local_collections_screen.dart';
import 'local_entity_browser_screen.dart';
import 'local_media_library_screen_v2.dart';

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

  List<Widget> get _pages => const [
        LocalMediaLibraryScreenV2(),
        LocalEntityBrowserScreen(kind: LocalEntityBrowserKind.artists),
        LocalEntityBrowserScreen(kind: LocalEntityBrowserKind.albums),
        LocalCollectionsScreen(view: LocalCollectionView.favorites),
        LocalCollectionsScreen(view: LocalCollectionView.playlists),
      ];

  @override
  Widget build(BuildContext context) {
    final desktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (desktop && constraints.maxWidth >= 880) {
          return ColoredBox(
            color: AppColors.bgBase,
            child: Row(
              children: [
                NavigationRail(
                  backgroundColor: AppColors.bgElevated,
                  selectedIndex: _index,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (value) => setState(() => _index = value),
                  leading: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Icon(Icons.library_music_rounded, size: 30),
                  ),
                  destinations: const [
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
                  ],
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
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: const [
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
            ],
          ),
        );
      },
    );
  }
}
