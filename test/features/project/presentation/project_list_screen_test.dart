import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';
import 'package:lyric_forge_ktv/features/project/presentation/project_list_dependencies.dart';
import 'package:lyric_forge_ktv/features/project/presentation/screens/project_list_screen.dart';
import 'package:lyric_forge_ktv/features/project/presentation/screens/project_trash_screen.dart';

import '../support/fake_project_deletion_service.dart';

ProjectManifest _project(
  String id, {
  String name = 'Light My Fire',
  String path = '/music/light.mp3',
  bool lyrics = false,
  int day = 1,
}) => ProjectManifest(
  id: id,
  name: name,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026, 12, day),
  currentStage: lyrics
      ? ProcessingStage.lyricsEdited
      : ProcessingStage.audioImported,
  audioAsset: AudioAsset(originalPath: path, format: 'mp3'),
  lyricDocument: lyrics
      ? const LyricDocument(
          language: 'en',
          lines: [
            LyricLine(
              text: 'Come on baby',
              startTime: Duration.zero,
              endTime: Duration(seconds: 2),
            ),
          ],
        )
      : null,
);

void main() {
  late _Projects projects;
  late FakeProjectDeletionService deletion;

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
        home: ProjectListScreen(
          dependencies: ProjectListDependencies(
            projectRepository: projects,
            deletionService: deletion,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    expect(find.byKey(const ValueKey('project_delete_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('project_delete_confirm')));
    await tester.pumpAndSettle();
  }

  setUp(() {
    projects = _Projects([
      _project('kept', lyrics: true, day: 3),
      _project('dup-1', day: 5),
      _project('dup-2', day: 7),
      _project('other', name: 'Riders on the Storm', path: '/music/r.mp3'),
    ]);
    deletion = FakeProjectDeletionService(
      removeProject: projects.deleteProject,
      addProject: projects.restore,
    );
  });

  testWidgets('cleans up a song recognised several times in one go', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('4 个工程'), findsOneWidget);
    expect(find.text('1 首歌有重复的工程，共多出 2 个'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('project_list_clean_duplicates')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('保留“Light My Fire”（只有它有歌词），删除另外 2 个重复的工程。'),
      findsOneWidget,
    );
    expect(find.text('删除 2 个工程？'), findsOneWidget);
    await confirm(tester);

    expect(deletion.deleted, unorderedEquals(['dup-1', 'dup-2']));
    expect(find.text('已删除 2 个工程，可在“最近删除”恢复'), findsOneWidget);
    expect(find.text('2 个工程'), findsOneWidget);
    expect(find.text('最近删除（2）'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('project_list_duplicates_banner')),
      findsNothing,
    );
  });

  testWidgets('only the duplicates, with the one to keep marked', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(
      find.byKey(const ValueKey('project_list_show_duplicates')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('project_row_other')), findsNothing);
    expect(find.text('建议保留'), findsOneWidget);
    expect(find.text('重复'), findsNWidgets(2));
  });

  testWidgets('one project goes at once and 撤销 brings it back', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('project_menu_other')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('project_delete_other')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('project_delete_dialog')), findsNothing);
    expect(deletion.deleted, ['other']);
    expect(find.text('工程已移到“最近删除”'), findsOneWidget);
    expect(find.byKey(const ValueKey('project_row_other')), findsNothing);
    expect(find.text('最近删除（1）'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(deletion.restored, ['other']);
    expect(find.text('工程已恢复'), findsOneWidget);
    expect(find.byKey(const ValueKey('project_row_other')), findsOneWidget);
    expect(find.text('4 个工程'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('project_list_trash_entry')),
      findsNothing,
    );
  });

  testWidgets('cancel keeps a selection', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('project_list_select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('project_row_dup-1')));
    await tester.tap(find.byKey(const ValueKey('project_row_other')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('project_list_delete_selected')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('30 天内可以恢复'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('project_delete_cancel')));
    await tester.pumpAndSettle();

    expect(deletion.deleted, isEmpty);
    expect(find.text('4 个工程'), findsOneWidget);
  });

  testWidgets('最近删除 opens from the list and restores', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('project_menu_other')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('project_delete_other')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('project_list_trash')));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectTrashScreen), findsOneWidget);
    expect(find.text('Riders on the Storm'), findsOneWidget);
    expect(find.text('还剩 30 天'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('project_trash_restore_other')),
    );
    await tester.pumpAndSettle();
    expect(deletion.restored, ['other']);
    expect(
      find.byKey(const ValueKey('project_trash_empty_state')),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('project_row_other')), findsOneWidget);
  });

  testWidgets('deletes a selection', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('project_list_select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('project_row_dup-1')));
    await tester.tap(find.byKey(const ValueKey('project_row_other')));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 个'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('project_list_delete_selected')),
    );
    await tester.pumpAndSettle();
    await confirm(tester);

    expect(deletion.deleted, unorderedEquals(['dup-1', 'other']));
    expect(find.text('2 个工程'), findsOneWidget);
    expect(find.text('全部工程'), findsOneWidget);
  });

  testWidgets('a project in use is not offered for deletion', (tester) async {
    deletion.blockers['other'] = '这首歌正在播放，换一首或停止播放后再删除';
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('project_menu_other')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('project_delete_other')));
    await tester.pumpAndSettle();

    expect(find.text('这首歌正在播放，换一首或停止播放后再删除'), findsOneWidget);
    expect(deletion.deleted, isEmpty);
  });

  testWidgets('fits a narrow phone at double text size', (tester) async {
    await pump(tester, size: const Size(320, 568), textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.tap(
      find.byKey(const ValueKey('project_list_clean_duplicates')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('project_delete_dialog')), findsOneWidget);
  });

  testWidgets('search narrows the list', (tester) async {
    await pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('project_list_search')),
      'riders',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('project_row_other')), findsOneWidget);
    expect(find.byKey(const ValueKey('project_row_kept')), findsNothing);
  });
}

class _Projects extends Fake implements ProjectRepository {
  _Projects(List<ProjectManifest> projects)
    : _byId = {for (final project in projects) project.id: project};

  final Map<String, ProjectManifest> _byId;

  @override
  Future<List<ProjectManifest>> getAllProjects() async =>
      _byId.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<void> deleteProject(String id) async {
    _byId.remove(id);
  }

  Future<void> restore(ProjectManifest project) async {
    _byId[project.id] = project;
  }
}
