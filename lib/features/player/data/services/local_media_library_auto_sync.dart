import '../../domain/repositories/local_media_library_repository.dart';

typedef LocalLibraryClock = DateTime Function();

/// Coordinates lightweight background rescans of persisted music folders.
///
/// Multiple callers (app lifecycle + library screen) share one in-flight scan,
/// and foreground resumes are throttled so a large library is not recursively
/// walked every time focus changes.
class LocalMediaLibraryAutoSync {
  final LocalMediaLibraryRepository libraryRepository;
  final List<String> supportedExtensions;
  final Duration minimumInterval;
  final LocalLibraryClock clock;

  DateTime? _lastCompletedAt;
  Future<bool>? _inFlight;

  LocalMediaLibraryAutoSync({
    required this.libraryRepository,
    required Iterable<String> supportedExtensions,
    this.minimumInterval = const Duration(minutes: 5),
    LocalLibraryClock? clock,
  })  : supportedExtensions = List.unmodifiable(
          supportedExtensions.map((value) => value.toLowerCase()).toSet(),
        ),
        clock = clock ?? DateTime.now;

  DateTime? get lastCompletedAt => _lastCompletedAt;

  Future<bool> sync({bool force = false}) {
    final active = _inFlight;
    if (active != null) return active;

    final operation = _sync(force: force);
    _inFlight = operation;
    return operation.whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
    });
  }

  Future<bool> _sync({required bool force}) async {
    final roots = await libraryRepository.getRoots();
    if (roots.isEmpty || supportedExtensions.isEmpty) return false;

    final now = clock();
    final last = _lastCompletedAt;
    if (!force && last != null && now.difference(last) < minimumInterval) {
      return false;
    }

    await libraryRepository.refreshFromRoots(supportedExtensions);
    _lastCompletedAt = clock();
    return true;
  }
}
