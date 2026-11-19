import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_library_entry.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_library_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/library_folder_settings.dart';

void main() {
  late _MemoryFolderStore store;
  late _Library library;

  LibraryFolderSettings settings({String? system = '/home/me/Music'}) {
    return LibraryFolderSettings(
      store: store,
      library: library,
      systemMusicFolder: system,
    );
  }

  setUp(() {
    store = _MemoryFolderStore();
    library = _Library();
  });

  test('without a choice or library folders it is the system folder', () async {
    expect(
      await settings().current(),
      const LibraryFolder(
        path: '/home/me/Music',
        source: LibraryFolderSource.system,
      ),
    );
  });

  test('the first library folder the user added comes before it', () async {
    library.roots.addAll(['  ', '/data/songs', '/data/more']);

    final folder = await settings().current();

    expect(folder.path, '/data/songs');
    expect(folder.source, LibraryFolderSource.firstLibraryFolder);
    expect(folder.isCustom, isFalse);
  });

  test('an unreadable library store still leaves the system folder', () async {
    library.failRoots = true;

    final folder = await settings().current();

    expect(folder.source, LibraryFolderSource.system);
  });

  test('no folder at all is reported as none', () async {
    final folder = await settings(system: null).current();

    expect(folder, LibraryFolder.none);
    expect(await settings(system: null).currentPath(), isNull);
  });

  test('choosing a folder stores it and adds it to the library', () async {
    library.roots.add('/data/songs');

    final folder = await settings().choose('  /mnt/曲库  ');

    expect(folder.path, '/mnt/曲库');
    expect(folder.isCustom, isTrue);
    expect(store.saved, '/mnt/曲库');
    expect(library.roots, contains('/mnt/曲库'));
    expect(await settings().currentPath(), '/mnt/曲库');
  });

  test('an empty choice is refused', () async {
    await expectLater(settings().choose('   '), throwsArgumentError);
    expect(store.saved, isNull);
  });

  test('going back to the default forgets the choice only', () async {
    library.roots.add('/data/songs');
    await settings().choose('/mnt/曲库');

    final folder = await settings().resetToDefault();

    expect(store.saved, isNull);
    expect(folder.path, '/data/songs');
    // The chosen folder stays in the library; removing songs is separate.
    expect(library.roots, contains('/mnt/曲库'));
  });

  group('systemMusicFolder', () {
    test('Windows uses the user profile', () {
      expect(
        systemMusicFolder(
          operatingSystem: 'windows',
          environment: const {'USERPROFILE': r'C:\Users\me\'},
        ),
        r'C:\Users\me\Music',
      );
    });

    test('macOS and Linux use HOME', () {
      for (final os in ['macos', 'linux']) {
        expect(
          systemMusicFolder(
            operatingSystem: os,
            environment: const {'HOME': '/home/me'},
          ),
          '/home/me/Music',
        );
      }
    });

    test('Android uses the shared Music folder; iOS has none', () {
      expect(
        systemMusicFolder(operatingSystem: 'android', environment: const {}),
        '/storage/emulated/0/Music',
      );
      expect(
        systemMusicFolder(operatingSystem: 'ios', environment: const {}),
        isNull,
      );
    });

    test('an unknown home folder gives no default', () {
      expect(
        systemMusicFolder(
          operatingSystem: 'linux',
          environment: const {'HOME': '  '},
        ),
        isNull,
      );
    });
  });
}

class _MemoryFolderStore implements LibraryFolderStore {
  String? saved;

  @override
  Future<String?> loadFolder() async => saved;

  @override
  Future<void> saveFolder(String? path) async => saved = path;
}

class _Library implements LocalMediaLibraryRepository {
  final List<String> roots = [];
  bool failRoots = false;

  @override
  Future<List<String>> getRoots() async {
    if (failRoots) throw const FormatException('damaged library store');
    return List.of(roots);
  }

  @override
  Future<void> addRoot(String rootPath) async {
    if (!roots.contains(rootPath)) roots.add(rootPath);
  }

  @override
  Future<List<LocalMediaLibraryEntry>> getAll() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
