import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_appearance.dart';
import 'package:lyric_forge_ktv/core/theme/app_palette.dart';
import 'package:lyric_forge_ktv/features/settings/data/services/file_appearance_store.dart';

void main() {
  late Directory root;
  late FileAppearanceStore store;

  File preferenceFile() => File(
    '${root.path}${Platform.pathSeparator}${FileAppearanceStore.fileName}',
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('appearance_store');
    store = FileAppearanceStore(rootDirectory: root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('is an AppearanceStore', () {
    expect(store, isA<AppearanceStore>());
  });

  test('loads nothing before anything is saved', () async {
    expect(await store.load(), isNull);
    expect(preferenceFile().existsSync(), isFalse);
  });

  test('reads back every theme it saves', () async {
    for (final variant in AppThemeVariant.values) {
      await store.save(variant);
      expect(await store.load(), variant);
    }
  });

  test('a second store over the same folder sees the choice', () async {
    await store.save(AppThemeVariant.light);
    final again = FileAppearanceStore(rootDirectory: root);
    expect(await again.load(), AppThemeVariant.light);
  });

  test('writes versioned JSON with the theme id', () async {
    await store.save(AppThemeVariant.light);
    final decoded =
        jsonDecode(preferenceFile().readAsStringSync()) as Map<String, dynamic>;
    expect(decoded, {'version': 1, 'theme': 'light'});
  });

  test('overwrites the previous choice', () async {
    await store.save(AppThemeVariant.light);
    await store.save(AppThemeVariant.dark);
    final decoded =
        jsonDecode(preferenceFile().readAsStringSync()) as Map<String, dynamic>;
    expect(decoded[FileAppearanceStore.themeKey], 'dark');
    expect(await store.load(), AppThemeVariant.dark);
  });

  test('creates the folder when it is missing', () async {
    final nested = Directory(
      '${root.path}${Platform.pathSeparator}a${Platform.pathSeparator}b',
    );
    final deep = FileAppearanceStore(rootDirectory: nested);
    await deep.save(AppThemeVariant.light);
    expect(nested.existsSync(), isTrue);
    expect(await deep.load(), AppThemeVariant.light);
  });

  group('treats an unreadable file as nothing saved', () {
    Future<void> expectNothingFrom(String contents) async {
      preferenceFile().writeAsStringSync(contents);
      expect(await store.load(), isNull);
    }

    test('not JSON', () => expectNothingFrom('dark'));
    test('truncated JSON', () => expectNothingFrom('{"theme": "li'));
    test('a JSON list', () => expectNothingFrom('["light"]'));
    test('a JSON string', () => expectNothingFrom('"light"'));
    test('no theme key', () => expectNothingFrom('{"version": 1}'));
    test('a theme this version lacks', () {
      return expectNothingFrom('{"version": 1, "theme": "sepia"}');
    });
    test('a theme that is not a string', () {
      return expectNothingFrom('{"version": 1, "theme": 2}');
    });
    test('an empty file', () => expectNothingFrom(''));
  });

  test('reads a file from a newer version that added keys', () async {
    preferenceFile().writeAsStringSync(
      jsonEncode({'version': 2, 'theme': 'light', 'accent': 'violet'}),
    );
    expect(await store.load(), AppThemeVariant.light);
  });

  test('works with the controller end to end', () async {
    final first = AppAppearanceController(store: store);
    await first.restore();
    expect(first.variant, AppThemeVariant.dark);
    expect(await first.select(AppThemeVariant.light), isTrue);

    final relaunched = AppAppearanceController(
      store: FileAppearanceStore(rootDirectory: root),
    );
    await relaunched.restore();
    expect(relaunched.variant, AppThemeVariant.light);
  });

  test('a save that cannot write is reported to the controller', () async {
    // A file where the folder should be: creating the folder fails.
    final blocker = File('${root.path}${Platform.pathSeparator}blocked')
      ..writeAsStringSync('');
    final broken = FileAppearanceStore(rootDirectory: Directory(blocker.path));
    final controller = AppAppearanceController(store: broken);

    expect(await controller.select(AppThemeVariant.light), isFalse);
    expect(controller.variant, AppThemeVariant.light);
    expect(controller.saveError, isNotNull);
    expect(await broken.load(), isNull);
  });
}
