import 'package:flutter/material.dart';

import '../core/navigation/routes.dart';
import '../features/home/presentation/screens/dashboard_screen.dart';
import '../features/import/presentation/screens/transcription_ready_import_screen.dart';
import '../features/lyrics/presentation/screens/lyric_editor_screen.dart';
import '../features/lyrics/presentation/screens/review_inbox_screen.dart';
import '../features/player/domain/models/play_history.dart';
import '../features/player/presentation/screens/local_music_library_shell.dart';
import '../features/player/presentation/screens/now_playing_screen.dart';
import '../features/player/presentation/screens/player_screen.dart';
import '../features/player/presentation/screens/quick_play_screen.dart';
import '../features/project/presentation/screens/project_detail_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/transfer/presentation/screens/desktop_media_transfer_hub_v2_screen.dart';
import '../features/transfer/presentation/screens/media_hub_qr_scanner_screen.dart';
import '../features/transfer/presentation/screens/mobile_media_transfer_hub_screen.dart';
import '../features/transfer/presentation/screens/mobile_remote_library_shell.dart';
import 'app_services.dart';
import 'lyric_editor_assembly.dart';
import 'playback_assembly.dart';

/// The routing table: route name in, screen out.
///
/// This is assembly, not navigation. It was `AppRouter.onGenerateRoute`, a
/// static function that reached into the service locator for the one route that
/// needs live state (`/quick-play`). Taking [services] as a constructor argument
/// keeps that lookup explicit and lets a screen be handed exactly the
/// dependencies it declares instead of finding them itself (Phase 4.2).
class AppRouter {
  const AppRouter(this.services);

  final AppServices services;

  Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final uri = Uri.parse(settings.name ?? Routes.home);

    switch (uri.path) {
      case Routes.home:
      case Routes.dashboard:
        return _fadeRoute(const DashboardScreen(), settings);

      case Routes.import:
        return _fadeRoute(const TranscriptionReadyImportScreen(), settings);

      case Routes.library:
        return _fadeRoute(const LocalMusicLibraryShell(), settings);

      case Routes.libraryArtists:
        return _fadeRoute(
          const LocalMusicLibraryShell(initialIndex: 1),
          settings,
        );

      case Routes.libraryAlbums:
        return _fadeRoute(
          const LocalMusicLibraryShell(initialIndex: 2),
          settings,
        );

      case Routes.collections:
        return _fadeRoute(
          const LocalMusicLibraryShell(initialIndex: 3),
          settings,
        );

      case Routes.playlists:
        return _fadeRoute(
          const LocalMusicLibraryShell(initialIndex: 4),
          settings,
        );

      case Routes.quickPlay:
        final history = settings.arguments is PlayHistory
            ? settings.arguments as PlayHistory
            : null;
        if (history != null) {
          return _fadeRoute(QuickPlayScreen(initialHistory: history), settings);
        }
        final current =
            services.playbackSessionService.currentState.currentItem;
        if (current?.isRemoteStream == true) {
          return _fadeRoute(
            NowPlayingScreen(
              dependencies: assembleNowPlayingDependencies(services),
            ),
            settings,
          );
        }
        if (current != null) {
          return _fadeRoute(const QuickPlayScreen(), settings);
        }
        return _fadeRoute(const LocalMusicLibraryShell(), settings);

      case Routes.nowPlaying:
        return _fadeRoute(
          NowPlayingScreen(
            dependencies: assembleNowPlayingDependencies(services),
          ),
          settings,
        );

      case Routes.review:
        return _fadeRoute(
          ReviewInboxScreen(projectRepository: services.projectRepository),
          settings,
        );

      case Routes.settings:
        return _fadeRoute(const SettingsScreen(), settings);

      case Routes.mediaSharing:
        return _fadeRoute(const DesktopMediaTransferHubV2Screen(), settings);

      case Routes.remoteLibrary:
        return _fadeRoute(const MobileMediaTransferHubScreen(), settings);

      case Routes.remoteBrowse:
        return _fadeRoute(const MobileRemoteLibraryShell(), settings);

      case Routes.mediaHubScanner:
        return _fadeRoute(const MediaHubQrScannerScreen(), settings);

      default:
        if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'project') {
          final projectId = uri.pathSegments[1];

          if (uri.pathSegments.length == 2) {
            return _fadeRoute(
              ProjectDetailScreen(projectId: projectId),
              settings,
            );
          }

          if (uri.pathSegments.length == 3) {
            switch (uri.pathSegments[2]) {
              case 'lyrics':
                return _fadeRoute(
                  LyricEditorScreen(
                    projectId: projectId,
                    dependencies: assembleLyricEditorDependencies(services),
                  ),
                  settings,
                );
              case 'player':
                return _fadeRoute(
                  PlayerScreen(
                    projectId: projectId,
                    dependencies: assemblePlayerScreenDependencies(services),
                  ),
                  settings,
                );
            }
          }
        }

        return _fadeRoute(const DashboardScreen(), settings);
    }
  }

  static PageRoute<T> _fadeRoute<T>(Widget child, RouteSettings settings) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 200),
    );
  }
}
