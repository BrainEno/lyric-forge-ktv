import '../../player/domain/services/playback_session_service.dart';
import '../domain/global_search_source.dart';

/// What the global search is made of (D-065).
///
/// Bound in `lib/app/search_assembly.dart`. The search plays songs through
/// the shared session and leaves page changes to [openRoute], which the app
/// shell implements the way the navigation rail does, so 音乐库 or 设置
/// picked in the search land exactly where their rail buttons would.
class GlobalSearchDependencies {
  const GlobalSearchDependencies({
    required this.source,
    required this.playbackSession,
    required this.openRoute,
    this.phone = false,
  });

  final GlobalSearchSource source;
  final PlaybackSessionService playbackSession;

  /// Opens a page by route name.
  final void Function(String route) openRoute;

  /// A phone: no keyboard hints in the search.
  final bool phone;
}
