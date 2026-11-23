import 'global_search_item.dart';

/// Reads everything the global search can find (D-065): pages and actions,
/// projects (newest first, with their lyric lines), library songs and
/// playlists.
///
/// Read once each time the search opens, so it always reflects the latest
/// library without keeping an index up to date in the background.
abstract interface class GlobalSearchSource {
  Future<List<GlobalSearchItem>> load();
}
