import '../features/search/data/local_global_search_source.dart';
import '../features/search/presentation/global_search_dependencies.dart';
import 'app_services.dart';

/// What the global search (Ctrl/⌘+K) is made of (D-065).
///
/// [openRoute] comes from the app shell, which owns the navigator and the
/// rail's rules for top-level destinations.
GlobalSearchDependencies assembleGlobalSearchDependencies(
  AppServices services, {
  required bool phone,
  required void Function(String route) openRoute,
}) {
  return GlobalSearchDependencies(
    source: LocalGlobalSearchSource(
      projectRepository: services.projectRepository,
      libraryRepository: services.localMediaLibraryRepository,
      metadataRepository: services.localMediaMetadataRepository,
      collectionRepository: services.localMediaCollectionRepository,
      phone: phone,
    ),
    playbackSession: services.playbackSessionService,
    openRoute: openRoute,
    phone: phone,
  );
}
