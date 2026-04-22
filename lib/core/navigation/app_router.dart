import 'package:flutter/material.dart';
import '../../features/home/presentation/screens/dashboard_screen.dart';
import '../../features/project/presentation/screens/project_detail_screen.dart';
import '../../features/import/presentation/screens/import_audio_screen.dart';
import '../../features/lyrics/presentation/screens/lyric_editor_screen.dart';
import '../../features/player/presentation/screens/player_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';

abstract class Routes {
  static const String home = '/';
  static const String dashboard = '/dashboard';
  static const String import = '/import';
  static const String projectDetail = '/project/:id';
  static const String lyricEditor = '/project/:id/lyrics';
  static const String player = '/project/:id/player';
  static const String settings = '/settings';

  static String projectDetailPath(String id) => '/project/$id';
  static String lyricEditorPath(String id) => '/project/$id/lyrics';
  static String playerPath(String id) => '/project/$id/player';
}

class AppRouter {
  const AppRouter._();

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final uri = Uri.parse(settings.name ?? Routes.home);

    switch (uri.path) {
      case Routes.home:
      case Routes.dashboard:
        return _fadeRoute(const DashboardScreen(), settings);

      case Routes.import:
        return _fadeRoute(const ImportAudioScreen(), settings);

      case Routes.settings:
        return _fadeRoute(const SettingsScreen(), settings);

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
                  LyricEditorScreen(projectId: projectId),
                  settings,
                );
              case 'player':
                return _fadeRoute(PlayerScreen(projectId: projectId), settings);
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
