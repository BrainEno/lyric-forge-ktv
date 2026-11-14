import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_store_integrity.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/local_store_integrity_banner.dart';

const _libraryIssue = LocalStoreLoadIssue(
  kind: LocalStoreKind.mediaLibrary,
  storePath: '/data/media_library.json',
  unreadableRecords: 2,
  readableRecords: 40,
  detail: 'Library record 3 could not be read',
);

const _collectionsIssue = LocalStoreLoadIssue(
  kind: LocalStoreKind.collections,
  storePath: '/data/library_collections.json',
  unreadableRecords: 1,
  readableRecords: 5,
  detail: 'Playlist 2 could not be read',
);

void main() {
  testWidgets('explains each partly readable store and offers repair', (
    tester,
  ) async {
    final repaired = <LocalStoreKind>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalStoreIntegrityBanner(
            issues: const [_libraryIssue, _collectionsIssue],
            onRepair: (issue) => repaired.add(issue.kind),
          ),
        ),
      ),
    );

    expect(find.text('音乐库文件有 2 条记录无法读取'), findsOneWidget);
    expect(find.text('收藏与播放列表文件有 1 条记录无法读取'), findsOneWidget);
    expect(find.textContaining('已显示可读取的 40 条记录'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('repair_local_store_collections')),
    );
    expect(repaired, [LocalStoreKind.collections]);
  });

  testWidgets('disables repair while other library work runs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalStoreIntegrityBanner(
            issues: const [_libraryIssue],
            busy: true,
            onRepair: (_) => fail('must not repair while busy'),
          ),
        ),
      ),
    );
    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('repair_local_store_mediaLibrary')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('renders nothing without issues', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalStoreIntegrityBanner(issues: const [], onRepair: (_) {}),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('local_store_integrity_banner')),
      findsNothing,
    );
  });

  for (final confirm in [true, false]) {
    testWidgets('repair confirmation returns $confirm', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await confirmLocalStoreRepair(context, _libraryIssue);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('修复音乐库文件？'), findsOneWidget);
      expect(find.textContaining('.incomplete 副本'), findsOneWidget);
      expect(find.textContaining('/data/media_library.json'), findsOneWidget);
      await tester.tap(find.text(confirm ? '保留副本并修复' : '取消'));
      await tester.pumpAndSettle();
      expect(result, confirm);
    });
  }

  test(
    'describes write-protected stores in Chinese and keeps other errors',
    () {
      expect(
        describeLocalLibraryError(
          const LocalStoreIncompleteException(_collectionsIssue),
        ),
        contains('收藏与播放列表文件有 1 条记录无法读取'),
      );
      expect(describeLocalLibraryError(StateError('boom')), 'Bad state: boom');
    },
  );
}
