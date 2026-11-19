import '../repositories/local_media_library_repository.dart';

/// Persists the user's choice of library folder (曲库目录).
abstract class LibraryFolderStore {
  /// The folder the user chose, or null when they never chose one.
  Future<String?> loadFolder();

  /// Stores [path]; null forgets the choice and goes back to the default.
  Future<void> saveFolder(String? path);
}

/// Where the current library folder came from.
enum LibraryFolderSource {
  /// Chosen by the user in settings.
  custom,

  /// The first music folder the user added to the library.
  firstLibraryFolder,

  /// The system 音乐 folder.
  system,

  /// None of the above is known on this platform.
  none,
}

/// The library folder (曲库目录) and where it came from.
class LibraryFolder {
  const LibraryFolder({required this.path, required this.source});

  static const LibraryFolder none = LibraryFolder(
    path: null,
    source: LibraryFolderSource.none,
  );

  final String? path;
  final LibraryFolderSource source;

  bool get isCustom => source == LibraryFolderSource.custom;

  @override
  bool operator ==(Object other) =>
      other is LibraryFolder && other.path == path && other.source == source;

  @override
  int get hashCode => Object.hash(path, source);
}

/// The library folder: where exported lyric files are looked for, so a
/// lyric file saved there is paired with its song automatically, and where
/// lyric exports are saved by default (decision D-033).
///
/// Without a choice the folder is the first music folder the user added to
/// the library, then the system 音乐 folder. Choosing a folder also adds it
/// to the library, so songs stored there are scanned too; the default is
/// never added by itself, because quietly importing a whole 音乐 folder is
/// not what anyone asked for.
class LibraryFolderSettings {
  LibraryFolderSettings({
    required LibraryFolderStore store,
    required LocalMediaLibraryRepository library,
    required String? systemMusicFolder,
  }) : _store = store,
       _library = library,
       _systemMusicFolder = systemMusicFolder;

  final LibraryFolderStore _store;
  final LocalMediaLibraryRepository _library;
  final String? _systemMusicFolder;

  /// The folder in effect now.
  Future<LibraryFolder> current() async {
    final custom = _clean(await _store.loadFolder());
    if (custom != null) {
      return LibraryFolder(path: custom, source: LibraryFolderSource.custom);
    }
    try {
      final roots = await _library.getRoots();
      for (final root in roots) {
        final cleaned = _clean(root);
        if (cleaned == null) continue;
        return LibraryFolder(
          path: cleaned,
          source: LibraryFolderSource.firstLibraryFolder,
        );
      }
    } on Exception {
      // An unreadable library store must not hide the system default.
    }
    final system = _clean(_systemMusicFolder);
    if (system != null) {
      return LibraryFolder(path: system, source: LibraryFolderSource.system);
    }
    return LibraryFolder.none;
  }

  /// Just the path, for callers such as the export dialog.
  Future<String?> currentPath() async => (await current()).path;

  /// Makes [path] the library folder and adds it to the library.
  Future<LibraryFolder> choose(String path) async {
    final cleaned = _clean(path);
    if (cleaned == null) {
      throw ArgumentError.value(path, 'path', 'must not be empty');
    }
    await _store.saveFolder(cleaned);
    await _library.addRoot(cleaned);
    return current();
  }

  /// Forgets the user's choice. The folder stays in the library: removing
  /// songs is a separate decision.
  Future<LibraryFolder> resetToDefault() async {
    await _store.saveFolder(null);
    return current();
  }

  static String? _clean(String? path) {
    final trimmed = path?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

/// The system 音乐 folder for [operatingSystem], from the user's [environment].
///
/// Returns null where the platform has no such folder the app can read
/// without a picker (iOS) or when the home folder is unknown.
String? systemMusicFolder({
  required String operatingSystem,
  required Map<String, String> environment,
}) {
  String? home(List<String> keys) {
    for (final key in keys) {
      final value = environment[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String join(String base, String child, String separator) {
    final trimmed = base.endsWith(separator)
        ? base.substring(0, base.length - 1)
        : base;
    return '$trimmed$separator$child';
  }

  switch (operatingSystem) {
    case 'windows':
      final profile = home(const ['USERPROFILE', 'HOME']);
      return profile == null ? null : join(profile, 'Music', r'\');
    case 'macos':
    case 'linux':
      final profile = home(const ['HOME']);
      return profile == null ? null : join(profile, 'Music', '/');
    case 'android':
      return '/storage/emulated/0/Music';
    default:
      return null;
  }
}
