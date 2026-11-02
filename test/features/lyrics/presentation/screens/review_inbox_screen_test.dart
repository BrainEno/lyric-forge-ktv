import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lyric_forge_ktv/features/lyrics/presentation/screens/review_inbox_screen.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';

ProjectManifest _project({
  required String id,
  required String name,
  String? artist,
  DateTime? updatedAt,
  List<LyricLine>? lines,
}) {
  final at = updatedAt ?? DateTime(2026, 11, 1);
  return ProjectManifest(
    id: id,
    name: name,
    artist: artist,
    createdAt: at,
    updatedAt: at,
    lyricDocument: lines == null
        ? null
        : LyricDocument(language: 'zh', lines: lines),
  );
}

LyricLine _line(String text, {int confidence = 95, int startSeconds = 0}) {
  return LyricLine(
    text: text,
    startTime: Duration(seconds: startSeconds),
    endTime: Duration(seconds: startSeconds + 4),
    confidence: confidence,
  );
}

class _FakeProjectRepository implements ProjectRepository {
  _FakeProjectRepository(List<ProjectManifest> projects)
    : projects = List<ProjectManifest>.of(projects);

  final List<ProjectManifest> projects;
  bool fail = false;
  int calls = 0;

  @override
  Future<List<ProjectManifest>> getAllProjects() async {
    calls++;
    if (fail) throw const ProjectRepositoryException('boom');
    return projects;
  }

  @override
  Future<List<ProjectManifest>> getRecentProjects({int limit = 10}) async =>
      projects.take(limit).toList();

  @override
  Future<ProjectManifest?> getProjectById(String id) async {
    for (final project in projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  @override
  Future<ProjectManifest> createProject({
    required String name,
    String? artist,
    String? album,
  }) async => throw UnimplementedError();

  @override
  Future<ProjectManifest> updateProject(ProjectManifest project) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteProject(String id) async {}
}

void main() {
  late _FakeProjectRepository repository;
  late List<String> pushedRoutes;

  setUp(() {
    pushedRoutes = <String>[];
    repository = _FakeProjectRepository(const []);
  });

  Widget buildScreen() => MaterialApp(
    onGenerateRoute: (settings) {
      pushedRoutes.add(settings.name ?? '');
      return MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('编辑器')),
      );
    },
    home: ReviewInboxScreen(projectRepository: repository),
  );

  testWidgets('没有歌词工程时说明下一步', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('还没有可校对的歌词'), findsOneWidget);
    expect(find.text('去导入'), findsOneWidget);
  });

  testWidgets('只列出有歌词的工程，并按待复核行数排序', (tester) async {
    repository = _FakeProjectRepository([
      _project(id: 'a', name: '干净的工程', lines: [_line('月亮代表我的心')]),
      _project(
        id: 'b',
        name: '应该先看的工程',
        artist: '某歌手',
        updatedAt: DateTime(2026, 10, 1),
        lines: [
          _line('第 1 行', confidence: 30),
          _line('第 2 行', confidence: 40, startSeconds: 4),
          _line('第 3 行', confidence: 95, startSeconds: 8),
        ],
      ),
      _project(id: 'c', name: '还没有歌词'),
    ]);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    // The project list is filtered, not padded with empty entries.
    expect(find.text('还没有歌词'), findsNothing);
    expect(find.text('干净的工程'), findsOneWidget);
    expect(find.text('应该先看的工程'), findsOneWidget);

    // Most outstanding work first, even though it was updated a month earlier.
    final first = tester.getTopLeft(find.text('应该先看的工程')).dy;
    final second = tester.getTopLeft(find.text('干净的工程')).dy;
    expect(first, lessThan(second));

    expect(find.text('待复核 2'), findsOneWidget);
    expect(find.text('低置信度 2'), findsOneWidget);
    expect(find.text('已复核'), findsOneWidget);
    expect(find.textContaining('共 2 行待复核'), findsOneWidget);
  });

  testWidgets('点一行进入该工程的歌词编辑器', (tester) async {
    repository = _FakeProjectRepository([
      _project(id: 'abc', name: '月亮代表我的心', lines: [_line('月亮')]),
    ]);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('月亮代表我的心'));
    await tester.pumpAndSettle();

    expect(pushedRoutes, ['/project/abc/lyrics']);
    expect(find.text('编辑器'), findsOneWidget);
  });

  testWidgets('未评分的工程显示未评分而不是低置信度 0', (tester) async {
    repository = _FakeProjectRepository([
      _project(
        id: 'a',
        name: '未评分工程',
        lines: [
          LyricLine(
            text: '',
            startTime: Duration.zero,
            endTime: const Duration(seconds: 4),
            confidence: unscoredConfidencePlaceholder,
            confidenceSource: LyricConfidenceSource.unscored,
          ),
        ],
      ),
    ]);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('待复核 1'), findsOneWidget);
    expect(find.textContaining('低置信度'), findsNothing);
    expect(find.text('未评分 1'), findsOneWidget);
  });

  testWidgets('加载失败时给出重试', (tester) async {
    repository.fail = true;

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('工程列表加载失败'), findsOneWidget);

    repository.fail = false;
    repository.projects.add(
      _project(id: 'a', name: '恢复了', lines: [_line('月亮')]),
    );
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('恢复了'), findsOneWidget);
  });
}
