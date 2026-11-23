import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/services/project_deletion_service.dart';
import 'package:lyric_forge_ktv/features/project/presentation/screens/project_trash_screen.dart';

import '../support/fake_project_deletion_service.dart';

ProjectManifest _project(String id, String name) => ProjectManifest(
  id: id,
  name: name,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  late FakeProjectDeletionService service;
  final now = DateTime(2026, 12, 20);

  setUp(() {
    service = FakeProjectDeletionService()
      ..trash.addAll([
        TrashedProject(
          project: _project('new', 'Light My Fire'),
          deletedAt: DateTime(2026, 12, 18),
          hasFiles: true,
          bytes: 3 * 1024 * 1024,
        ),
        TrashedProject(
          project: _project('old', 'Riders on the Storm'),
          deletedAt: DateTime(2026, 11, 22),
        ),
      ]);
  });

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1280, 900),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ProjectTrashScreen(service: service, now: () => now),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists what is left, soonest to go flagged', (tester) async {
    await pump(tester);
    expect(find.text('Light My Fire'), findsOneWidget);
    expect(find.text('还剩 28 天'), findsOneWidget);
    expect(find.textContaining('含工程文件 3.0 MB'), findsOneWidget);
    expect(find.text('还剩 2 天'), findsOneWidget);
    expect(find.textContaining('保留 30 天'), findsOneWidget);
  });

  testWidgets('restores one', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('project_trash_restore_new')));
    await tester.pumpAndSettle();
    expect(service.restored, ['new']);
    expect(find.text('工程已恢复'), findsOneWidget);
    expect(find.byKey(const ValueKey('project_trash_row_new')), findsNothing);
  });

  testWidgets('deleting for good asks first', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('project_trash_purge_new')));
    await tester.pumpAndSettle();
    expect(find.text('彻底删除“Light My Fire”？'), findsOneWidget);
    expect(find.textContaining('3.0 MB'), findsNWidgets(2));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(service.purged, isEmpty);

    await tester.tap(find.byKey(const ValueKey('project_trash_purge_new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('project_trash_confirm')));
    await tester.pumpAndSettle();
    expect(service.purged, ['new']);
    expect(find.text('已彻底删除'), findsOneWidget);
  });

  testWidgets('清空 empties it after asking', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('project_trash_empty')));
    await tester.pumpAndSettle();
    expect(find.text('2 个工程会彻底删除，不能恢复。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('project_trash_confirm')));
    await tester.pumpAndSettle();

    expect(service.purged, unorderedEquals(['new', 'old']));
    expect(
      find.byKey(const ValueKey('project_trash_empty_state')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('project_trash_empty')), findsNothing);
  });

  testWidgets('a restore that fails says why', (tester) async {
    await pump(tester);
    service.trash.clear();
    await tester.tap(find.byKey(const ValueKey('project_trash_restore_old')));
    await tester.pumpAndSettle();
    expect(find.text('“最近删除”里已经没有这个工程'), findsOneWidget);
  });

  testWidgets('fits a narrow phone at double text size', (tester) async {
    await pump(tester, size: const Size(320, 568), textScale: 2);
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('project_trash_restore_new')),
      findsOneWidget,
    );
  });
}
