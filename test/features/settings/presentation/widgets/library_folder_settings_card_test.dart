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

  Widget host({bool withFinder = true}) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: LibraryFolderSettingsCard(
          settings: settings(),
          pickFolder: pick,
          findLyrics: withFinder ? findLyricFiles : null,
        ),
      ),
    ),
  );

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
