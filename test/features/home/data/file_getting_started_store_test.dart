import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/home/data/services/file_getting_started_store.dart';
import 'package:lyric_forge_ktv/features/home/domain/models/getting_started.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('getting_started_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('nothing saved reads as null', () async {
    final store = FileGettingStartedStore(rootDirectory: root);
    expect(await store.load(), isNull);
  });

  test('saves and reads the visibility and the KTV step', () async {
    final store = FileGettingStartedStore(rootDirectory: root);

    await store.save(
      const GettingStartedPreferences(
        visibility: GettingStartedVisibility.dismissed,
        openedKtv: true,
      ),
    );
    final loaded = await store.load();

    expect(loaded?.visibility, GettingStartedVisibility.dismissed);
    expect(loaded?.openedKtv, isTrue);
  });

  test('a file it did not write reads as null', () async {
    await File(
      '${root.path}${Platform.pathSeparator}'
      '${FileGettingStartedStore.fileName}',
    ).writeAsString('not json');
    final store = FileGettingStartedStore(rootDirectory: root);

    expect(await store.load(), isNull);
  });
}
