import 'package:flutter/material.dart';

import '../../../../core/navigation/app_navigation_shell.dart';
import '../../../../core/theme/color_tokens.dart';
import '../transfer_screen_dependencies.dart';
import 'mobile_download_manager_screen.dart';
import 'mobile_remote_grouped_library_screen.dart';
import 'mobile_remote_music_library_screen.dart';

/// Bottom-navigation shell of the desktop library on the phone
/// (`Routes.remoteBrowse`). Each tab is its own screen over the same
/// dependencies: songs ([MobileRemoteMusicLibraryScreen]), artists and
/// albums ([MobileRemoteGroupedLibraryScreen]), downloads
/// ([MobileDownloadManagerScreen]).
class MobileRemoteLibraryShell extends StatefulWidget {
  final MobileRemoteLibraryDependencies dependencies;

  const MobileRemoteLibraryShell({super.key, required this.dependencies});

  @override
  State<MobileRemoteLibraryShell> createState() =>
      _MobileRemoteLibraryShellState();
}

class _MobileRemoteLibraryShellState extends State<MobileRemoteLibraryShell> {
  int _index = 0;

  Widget _pageForIndex() {
    return switch (_index) {
      0 => MobileRemoteMusicLibraryScreen(dependencies: widget.dependencies),
      1 => MobileRemoteGroupedLibraryScreen(
        view: RemoteCatalogView.artists,
        dependencies: widget.dependencies,
      ),
      2 => MobileRemoteGroupedLibraryScreen(
        view: RemoteCatalogView.albums,
        dependencies: widget.dependencies,
      ),
      _ => MobileDownloadManagerScreen(dependencies: widget.dependencies),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: _pageForIndex(),
      bottomNavigationBar: NavigationBar(
        // As low as the app's own tab bar (D-058).
        height: AppMobileBottomNavigation.barHeight,
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const <NavigationDestination>[
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
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download_done_rounded),
            label: '下载',
          ),
        ],
      ),
    );
  }
}
