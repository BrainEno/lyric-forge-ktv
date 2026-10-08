import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../widgets/local_library_folder_manager_dialog.dart';
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

class _LocalMusicLibraryShellState extends State<LocalMusicLibraryShell>
    with WidgetsBindingObserver {
  late int _index;
  int _libraryRevision = 0;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, 4).toInt();
    WidgetsBinding.instance.addObserver(this);
    // ServiceLocator already starts a non-blocking scan at app startup. This
    // joins that scan (or reuses its fresh result) and then refreshes visible
    // library tabs so newly-discovered songs appear without a manual button.
    unawaited(_syncLibrary());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncLibrary());
    }
  }

  @override
  void didUpdateWidget(covariant LocalMusicLibraryShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _index = widget.initialIndex.clamp(0, 4).toInt();
    }
  }

  Future<void> _syncLibrary({bool force = false}) async {
    if (_syncing) return;
    _syncing = true;
    try {
      await ServiceLocatorGlobal.I.localMediaLibraryAutoSync.sync(force: force);
      if (mounted) setState(() => _libraryRevision++);
    } catch (_) {
      // The existing library remains usable when a removable/inaccessible
      // folder cannot be scanned. Manual refresh surfaces detailed errors in
      // the Songs tab.
    } finally {
      _syncing = false;
    }
  }

  Future<void> _openFolderManager(BuildContext context) async {
    final services = ServiceLocatorGlobal.I;
    await showLocalLibraryFolderManagerDialog(
      context,
      library: services.localMediaLibraryRepository,
      importer: services.audioLibraryImportService,
      onLibraryChanged: () async {
        if (mounted) setState(() => _libraryRevision++);
      },
    );
  }

  void _openTransfer(BuildContext context) {
    Navigator.pushNamed(
      context,
      AppResponsive.isDesktopTarget()
          ? Routes.mediaSharing
          : Routes.remoteLibrary,
    );
  }

  List<Widget> get _pages => [
        LocalLibraryExplorerScreen(
          key: ValueKey('library-songs-$_libraryRevision'),
        ),
        LocalArtistAlbumBrowserScreen(
          key: ValueKey('library-artists-$_libraryRevision'),
          view: LocalCatalogView.artists,
        ),
        LocalArtistAlbumBrowserScreen(
          key: ValueKey('library-albums-$_libraryRevision'),
          view: LocalCatalogView.albums,
        ),
        LocalCollectionsScreen(
          key: ValueKey('library-favorites-$_libraryRevision'),
          view: LocalCollectionView.favorites,
        ),
        LocalCollectionsScreen(
          key: ValueKey('library-playlists-$_libraryRevision'),
          view: LocalCollectionView.playlists,
        ),
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
                  onDestinationSelected: (value) => setState(() => _index = value),
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.library_music_rounded, size: 30),
                        const SizedBox(height: 12),
                        IconButton.filledTonal(
                          tooltip: '音乐文件夹',
                          onPressed: () => _openFolderManager(context),
                          icon: const Icon(Icons.folder_special_rounded),
                        ),
                        const SizedBox(height: 8),
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
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'local-library-folders',
                tooltip: '音乐文件夹',
                onPressed: () => _openFolderManager(context),
                child: const Icon(Icons.folder_special_rounded),
              ),
              const SizedBox(height: 10),
              FloatingActionButton.small(
                heroTag: 'local-library-transfer',
                tooltip: '跨设备传输',
                onPressed: () => _openTransfer(context),
                child: const Icon(Icons.devices_rounded),
              ),
            ],
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
