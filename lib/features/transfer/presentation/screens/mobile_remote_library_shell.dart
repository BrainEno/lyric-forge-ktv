import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import 'mobile_download_manager_screen.dart';
import 'mobile_remote_grouped_library_screen.dart';
import 'mobile_remote_music_library_screen.dart';

class MobileRemoteLibraryShell extends StatefulWidget {
  const MobileRemoteLibraryShell({super.key});

  @override
  State<MobileRemoteLibraryShell> createState() =>
      _MobileRemoteLibraryShellState();
}

class _MobileRemoteLibraryShellState extends State<MobileRemoteLibraryShell> {
  int _index = 0;

  Widget _pageForIndex() {
    return switch (_index) {
      0 => const MobileRemoteMusicLibraryScreen(),
      1 => const MobileRemoteGroupedLibraryScreen(view: RemoteCatalogView.artists),
      2 => const MobileRemoteGroupedLibraryScreen(view: RemoteCatalogView.albums),
      _ => const MobileDownloadManagerScreen(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: _pageForIndex(),
      bottomNavigationBar: NavigationBar(
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
