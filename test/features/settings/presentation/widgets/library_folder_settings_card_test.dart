import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_library_entry.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_library_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/library_folder_settings.dart';
import 'package:lyric_forge_ktv/features/settings/presentation/widgets/library_folder_settings_card.dart';

void main() {
  late _Store store;
  late _Library library;
  late List<String?> pickerStarts;
  String? nextPick;
  late int finds;
  Completer<String>? findGate;
  late int autoPaired;
  late int counts;
  late int opens;
  Completer<void>? openGate;

  LibraryFolderSettings settings() => LibraryFolderSettings(
    store: store,
    library: library,
    systemMusicFolder: '/home/me/Music',
  );

  Future<String?> pick({String? initialDirectory}) async {
    pickerStarts.add(initialDirectory);
    return nextPick;
  }

  Future<String> findLyricFiles() async {
    finds++;
    final gate = findGate;
    if (gate != null) return gate.future;
    return '已为 2 首歌配上歌词文件';
  }

  Future<int> countAutoPaired() async {
    counts++;
    return autoPaired;
  }

  Future<void> openAutoPaired() async {
    opens++;
    await openGate?.future;
  }

  Widget host({
    bool withFinder = true,
    bool withCount = false,
    bool withOpen = true,
  }) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: LibraryFolderSettingsCard(
          settings: settings(),
          pickFolder: pick,
          findLyrics: withFinder ? findLyricFiles : null,
          countAutoPaired: withCount ? countAutoPaired : null,
          openAutoPaired: withOpen ? openAutoPaired : null,
        ),
      ),
    ),
  );

  String? autoPairedLine(WidgetTester tester) {
    final line = find.byKey(LibraryFolderSettingsCard.autoPairedKey);
    if (line.evaluate().isEmpty) return null;
    return tester.widget<Text>(line).data;
  }

  Finder button(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
  );

  String shownPath(WidgetTester tester) {
    final text = tester.widget<SelectableText>(
      find.byKey(LibraryFolderSettingsCard.pathKey),
    );
    return text.data!;
  }

  setUp(() {
    store = _Store();
    library = _Library();
    pickerStarts = [];
    nextPick = null;
    finds = 0;
    findGate = null;
    autoPaired = 0;
    counts = 0;
    opens = 0;
    openGate = null;
  });

  testWidgets('shows the default folder and where it comes from', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(shownPath(tester), '/home/me/Music');
    expect(find.text('默认：系统“音乐”文件夹'), findsOneWidget);
    expect(find.text(LibraryFolderSettingsText.matchingRule), findsOneWidget);
    expect(find.text(LibraryFolderSettingsText.change), findsOneWidget);
    // Nothing custom to go back from.
    expect(find.text(LibraryFolderSettingsText.reset), findsNothing);
    expect(find.text(LibraryFolderSettingsText.findNow), findsOneWidget);
  });

  testWidgets('the first library folder is the default when there is one', (
    tester,
  ) async {
    library.roots.add('/data/songs');

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(shownPath(tester), '/data/songs');
    expect(find.text('默认：你最先添加到音乐库的文件夹'), findsOneWidget);
  });

  testWidgets('choosing a folder saves it, adds it and pairs lyrics', (
    tester,
  ) async {
    nextPick = '/mnt/曲库';
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(button(LibraryFolderSettingsText.change));
    await tester.pumpAndSettle();

    expect(pickerStarts, ['/home/me/Music']);
    expect(store.folder, '/mnt/曲库');
    expect(library.roots, ['/mnt/曲库']);
    expect(finds, 1);
    expect(shownPath(tester), '/mnt/曲库');
    expect(find.text('你选择的文件夹'), findsOneWidget);
    expect(
      find.text('曲库目录已改为 /mnt/曲库，里面的歌曲也会加入音乐库。已为 2 首歌配上歌词文件'),
      findsOneWidget,
    );
    expect(find.text(LibraryFolderSettingsText.reset), findsOneWidget);
  });

  testWidgets('cancelling the picker changes nothing', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(button(LibraryFolderSettingsText.change));
    await tester.pumpAndSettle();

    expect(store.folder, isNull);
    expect(library.roots, isEmpty);
    expect(finds, 0);
    expect(find.byKey(LibraryFolderSettingsCard.messageKey), findsNothing);
  });

  testWidgets('going back to the default', (tester) async {
    store.folder = '/mnt/曲库';
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('你选择的文件夹'), findsOneWidget);

    await tester.tap(button(LibraryFolderSettingsText.reset));
    await tester.pumpAndSettle();

    expect(store.folder, isNull);
    expect(shownPath(tester), '/home/me/Music');
    expect(find.text(LibraryFolderSettingsText.resetDone), findsOneWidget);
    expect(find.text(LibraryFolderSettingsText.reset), findsNothing);
  });

  testWidgets('pairing on request shows progress, then the result', (
    tester,
  ) async {
    findGate = Completer<String>();
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(button(LibraryFolderSettingsText.findNow));
    await tester.pump();

    expect(find.text(LibraryFolderSettingsText.findNow), findsNothing);
    final change = tester.widget<ButtonStyleButton>(
      button(LibraryFolderSettingsText.change),
    );
    expect(change.onPressed, isNull);

    findGate!.complete('没有找到能配对的新歌词文件');
    await tester.pumpAndSettle();

    expect(find.text('没有找到能配对的新歌词文件'), findsOneWidget);
    expect(find.text(LibraryFolderSettingsText.findNow), findsOneWidget);
  });

  testWidgets('without a finder the pairing button is hidden', (tester) async {
    await tester.pumpWidget(host(withFinder: false));
    await tester.pumpAndSettle();

    expect(find.text(LibraryFolderSettingsText.findNow), findsNothing);
  });

  testWidgets('a failed save is shown in the readable error red', (
    tester,
  ) async {
    store.failSave = true;
    nextPick = '/mnt/曲库';
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(button(LibraryFolderSettingsText.change));
    await tester.pumpAndSettle();

    final message = tester.widget<Text>(
      find.byKey(LibraryFolderSettingsCard.messageKey),
    );
    expect(message.data, LibraryFolderSettingsText.saveFailed);
    expect(message.style?.color, AppColors.errorText);
    expect(shownPath(tester), '/home/me/Music');
  });

  group('automatic pairings (D-034)', () {
    testWidgets('says how many songs were paired and links to them', (
      tester,
    ) async {
      autoPaired = 3;
      await tester.pumpWidget(host(withCount: true));
      await tester.pumpAndSettle();

      expect(autoPairedLine(tester), '已自动配对 3 首歌');
      expect(counts, 1);

      await tester.tap(button(LibraryFolderSettingsText.openAutoPaired));
      await tester.pumpAndSettle();
      expect(opens, 1);
    });

    testWidgets('coming back from the library counts again', (tester) async {
      autoPaired = 2;
      openGate = Completer<void>();
      await tester.pumpWidget(host(withCount: true));
      await tester.pumpAndSettle();

      await tester.tap(button(LibraryFolderSettingsText.openAutoPaired));
      await tester.pumpAndSettle();
      // The user unpairs one song in the library, then comes back.
      autoPaired = 1;
      expect(autoPairedLine(tester), '已自动配对 2 首歌');

      openGate!.complete();
      await tester.pumpAndSettle();

      expect(counts, 2);
      expect(autoPairedLine(tester), '已自动配对 1 首歌');
    });

    testWidgets('with none yet there is nothing to open', (tester) async {
      await tester.pumpWidget(host(withCount: true));
      await tester.pumpAndSettle();

      expect(autoPairedLine(tester), LibraryFolderSettingsText.noneAutoPaired);
      expect(find.text(LibraryFolderSettingsText.openAutoPaired), findsNothing);
    });

    testWidgets('pairing now updates the count', (tester) async {
      await tester.pumpWidget(host(withCount: true));
      await tester.pumpAndSettle();
      expect(autoPairedLine(tester), LibraryFolderSettingsText.noneAutoPaired);

      autoPaired = 2;
      await tester.tap(button(LibraryFolderSettingsText.findNow));
      await tester.pumpAndSettle();

      expect(finds, 1);
      expect(autoPairedLine(tester), '已自动配对 2 首歌');
      expect(
        find.text(LibraryFolderSettingsText.openAutoPaired),
        findsOneWidget,
      );
    });

    testWidgets('going back to the default does not count again', (
      tester,
    ) async {
      store.folder = '/mnt/曲库';
      await tester.pumpWidget(host(withCount: true));
      await tester.pumpAndSettle();

      await tester.tap(button(LibraryFolderSettingsText.reset));
      await tester.pumpAndSettle();

      expect(counts, 1);
    });

    testWidgets('a count that fails leaves the line out', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryFolderSettingsCard(
              settings: settings(),
              pickFolder: pick,
              countAutoPaired: () async => throw const FormatException('坏'),
              openAutoPaired: openAutoPaired,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(autoPairedLine(tester), isNull);
      expect(find.text(LibraryFolderSettingsText.openAutoPaired), findsNothing);
    });

    testWidgets('without a counter there is no line', (tester) async {
      autoPaired = 4;
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      expect(autoPairedLine(tester), isNull);
      expect(counts, 0);
    });

    testWidgets('without a way to open the library only the count shows', (
      tester,
    ) async {
      autoPaired = 4;
      await tester.pumpWidget(host(withCount: true, withOpen: false));
      await tester.pumpAndSettle();

      expect(autoPairedLine(tester), '已自动配对 4 首歌');
      expect(find.text(LibraryFolderSettingsText.openAutoPaired), findsNothing);
    });
  });

  testWidgets('with no folder at all it asks for one', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryFolderSettingsCard(
            settings: LibraryFolderSettings(
              store: store,
              library: library,
              systemMusicFolder: null,
            ),
            pickFolder: pick,
            findLyrics: findLyricFiles,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(shownPath(tester), LibraryFolderSettingsText.noFolder);
    expect(find.text(LibraryFolderSettingsText.choose), findsOneWidget);
    expect(find.text(LibraryFolderSettingsText.findNow), findsNothing);
  });
}

class _Store implements LibraryFolderStore {
  String? folder;
  bool failSave = false;

  @override
  Future<String?> loadFolder() async => folder;

  @override
  Future<void> saveFolder(String? path) async {
    if (failSave) throw const FormatException('read-only settings');
    folder = path;
  }
}

class _Library implements LocalMediaLibraryRepository {
  final List<String> roots = [];

  @override
  Future<List<String>> getRoots() async => List.of(roots);

  @override
  Future<void> addRoot(String rootPath) async => roots.add(rootPath);

  @override
  Future<List<LocalMediaLibraryEntry>> getAll() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
