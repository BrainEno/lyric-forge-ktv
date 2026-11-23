import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lyric_forge_ktv/core/widgets/app_artwork.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_manual_edit_marker_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_decision_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/screens/review_inbox_screen.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/review_inbox_global_review.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';

ProjectManifest _project({
  required String id,
  required String name,
  String? artist,
  DateTime? updatedAt,
  List<LyricLine>? lines,
  AudioAsset? audioAsset,
}) {
  final at = updatedAt ?? DateTime(2026, 11, 1);
  return ProjectManifest(
    id: id,
    name: name,
    artist: artist,
    createdAt: at,
    updatedAt: at,
    audioAsset: audioAsset,
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
  int writes = 0;

  /// Makes the next conditional update fail as if the editor saved first.
  bool conflictNext = false;

  /// Holds every conditional update until completed.
  Completer<void>? gate;

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
  Future<ProjectManifest> updateProjectIfUnchanged(
    ProjectManifest project, {
    required int expectedRevision,
  }) async {
    final pending = gate;
    if (pending != null) await pending.future;
    final index = projects.indexWhere((stored) => stored.id == project.id);
    final current = projects[index];
    if (conflictNext || current.revision != expectedRevision) {
      conflictNext = false;
      throw ProjectUpdateConflictException(currentProject: current);
    }
    writes++;
    final saved = project.copyWith(revision: expectedRevision + 1);
    projects[index] = saved;
    return saved;
  }

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

  testWidgets('只列出有歌词的工程，并按建议复核行数排序', (tester) async {
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
    expect(find.text('应该先看的工程'), findsOneWidget);

    // Fully reviewed projects are folded while others still wait.
    expect(find.text('干净的工程'), findsNothing);
    expect(find.text('已复核的工程 · 1 个'), findsOneWidget);
    await tester.tap(find.text('已复核的工程 · 1 个'));
    await tester.pumpAndSettle();
    expect(find.text('干净的工程'), findsOneWidget);
    expect(find.text('收起已复核的工程'), findsOneWidget);

    // Most outstanding work first, even though it was updated a month earlier.
    final first = tester.getTopLeft(find.text('应该先看的工程')).dy;
    final second = tester.getTopLeft(find.text('干净的工程')).dy;
    expect(first, lessThan(second));

    // The editor's words: one 建议复核 count, no separate 低置信度 badge, and
    // the reason underneath.
    expect(find.text('建议复核 2'), findsOneWidget);
    expect(find.textContaining('低置信度'), findsNothing);
    expect(find.textContaining('必看'), findsNothing);
    expect(find.text('主要原因：置信度低 2'), findsOneWidget);
    expect(find.text('已复核'), findsOneWidget);
    expect(find.text('2 个工程，共 2 行建议复核'), findsOneWidget);
  });

  testWidgets('必看的行多的工程排在前面，摘要说出必看行数', (tester) async {
    repository = _FakeProjectRepository([
      _project(
        id: 'many',
        name: '留意较多',
        lines: [
          _line('第 1 行', confidence: 40),
          _line('第 2 行', confidence: 40, startSeconds: 4),
          _line('第 3 行', confidence: 40, startSeconds: 8),
        ],
      ),
      _project(
        id: 'must',
        name: '有一行必看',
        updatedAt: DateTime(2026, 9, 1),
        lines: [_line('')],
      ),
    ]);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    final must = tester.getTopLeft(find.text('有一行必看')).dy;
    final many = tester.getTopLeft(find.text('留意较多')).dy;
    expect(must, lessThan(many));
    expect(find.text('2 个工程，共 4 行建议复核，其中 1 行必看'), findsOneWidget);
    expect(find.text('必看 1'), findsOneWidget);
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

  testWidgets('从编辑器返回后重新读取，刚保存的确认会反映在列表里', (tester) async {
    repository = _FakeProjectRepository([
      _project(id: 'p', name: '夜曲', lines: [_line('第 1 行', confidence: 20)]),
    ]);
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();
    expect(find.text('建议复核 1'), findsOneWidget);

    await tester.tap(find.text('夜曲'));
    await tester.pumpAndSettle();
    expect(find.text('编辑器'), findsOneWidget);

    // What the editor does: confirm the line, then save.
    final stored = repository.projects.single;
    final document = const LyricManualEditMarkerService().assignMissingLineIds(
      stored.lyricDocument!,
    );
    repository.projects[0] = stored.copyWith(
      lyricDocument: const LyricReviewDecisionService().setAllReviewed(
        document,
      ),
      revision: stored.revision + 1,
    );
    final readsBefore = repository.calls;

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(repository.calls, readsBefore + 1);
    expect(find.text('建议复核 1'), findsNothing);
    expect(find.text('已复核'), findsOneWidget);
    expect(find.textContaining('暂时没有建议复核的行'), findsOneWidget);
  });

  testWidgets('和编辑器一样按音频时长计算待复核', (tester) async {
    repository = _FakeProjectRepository([
      _project(
        id: 'p',
        name: '尾部超出',
        lines: [_line('开头'), _line('超出音频', startSeconds: 8)],
        audioAsset: const AudioAsset(
          originalPath: 'song.wav',
          format: 'wav',
          duration: Duration(seconds: 5),
        ),
      ),
    ]);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    // The second line starts after the song ends: the editor queues it, so
    // the inbox must not call the project fully reviewed.
    expect(find.text('建议复核 1'), findsOneWidget);
    expect(find.text('已复核'), findsNothing);
  });

  testWidgets('未评分的工程不显示低置信度 0', (tester) async {
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

    expect(find.text('建议复核 1'), findsOneWidget);
    expect(find.textContaining('低置信度'), findsNothing);
    // An empty line is strong evidence, so 必看 takes the second badge.
    expect(find.text('必看 1'), findsOneWidget);
    expect(find.text('主要原因：空歌词 1'), findsOneWidget);
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

  testWidgets('全部复核完时直接列出，不需要展开', (tester) async {
    repository = _FakeProjectRepository([
      _project(id: 'a', name: '第一首', lines: [_line('月亮')]),
      _project(id: 'b', name: '第二首', lines: [_line('星星')]),
    ]);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('第一首'), findsOneWidget);
    expect(find.text('第二首'), findsOneWidget);
    expect(find.textContaining('已复核的工程'), findsNothing);
    expect(find.textContaining('暂时没有建议复核的行'), findsOneWidget);
  });

  testWidgets('收起后已复核的工程再次隐藏', (tester) async {
    repository = _FakeProjectRepository([
      _project(id: 'a', name: '待处理', lines: [_line('第 1 行', confidence: 20)]),
      _project(id: 'b', name: '已完成', lines: [_line('星星')]),
    ]);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('review-inbox:reviewed-toggle'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('已完成'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('已完成'), findsNothing);
    expect(find.text('待处理'), findsOneWidget);
  });

  testWidgets('每一行用歌曲封面位，没有封面时显示歌词占位', (tester) async {
    repository = _FakeProjectRepository([
      _project(id: 'a', name: '没有封面', lines: [_line('月亮')]),
    ]);

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    final artwork = tester.widget<AppArtwork>(
      find.descendant(
        of: find.byKey(const ValueKey('review-inbox:a')),
        matching: find.byType(AppArtwork),
      ),
    );
    expect(artwork.path, isNull);
    expect(artwork.placeholderIcon, Icons.lyrics_outlined);
    expect(find.byIcon(Icons.lyrics_outlined), findsOneWidget);
  });

  group('全部标为已复核', () {
    Finder menuOf(String id) =>
        find.byKey(ValueKey('review-inbox:actions:$id'));

    Future<void> chooseMarkAll(WidgetTester tester, String id) async {
      await tester.tap(menuOf(id));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ReviewInboxScreen.markAllReviewedLabel));
      await tester.pumpAndSettle();
    }

    Finder confirmButton() => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(
        FilledButton,
        ReviewInboxScreen.markAllReviewedLabel,
      ),
    );

    ProjectManifest pendingProject() => _project(
      id: 'p',
      name: '待处理',
      lines: [
        _line('第 1 行', confidence: 20),
        _line('第 2 行', confidence: 30, startSeconds: 4),
        _line('第 3 行', startSeconds: 8),
      ],
    );

    testWidgets('只有还有待复核行的工程才有这个菜单', (tester) async {
      repository = _FakeProjectRepository([
        pendingProject(),
        _project(id: 'done', name: '已完成', lines: [_line('星星')]),
      ]);
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await tester.tap(find.text('已复核的工程 · 1 个'));
      await tester.pumpAndSettle();

      expect(menuOf('p'), findsOneWidget);
      expect(menuOf('done'), findsNothing);
      expect(
        find.byTooltip(ReviewInboxScreen.moreActionsTooltip),
        findsOneWidget,
      );
    });

    testWidgets('确认前说明会改多少行', (tester) async {
      repository = _FakeProjectRepository([pendingProject()]);
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await chooseMarkAll(tester, 'p');

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.textContaining('「待处理」的 3 行都会记为人工确认，建议复核的 2 行会移出列表。'),
        findsOneWidget,
      );
      expect(find.textContaining('重新列入建议复核'), findsOneWidget);
    });

    testWidgets('取消时什么都不写', (tester) async {
      repository = _FakeProjectRepository([pendingProject()]);
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await chooseMarkAll(tester, 'p');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(repository.writes, 0);
      expect(find.text('建议复核 2'), findsOneWidget);
    });

    testWidgets('确认后工程离开待复核队列，并可以撤销', (tester) async {
      repository = _FakeProjectRepository([pendingProject()]);
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await chooseMarkAll(tester, 'p');
      await tester.tap(confirmButton());
      await tester.pumpAndSettle();

      expect(repository.writes, 1);
      expect(find.text(ReviewInboxScreen.markedMessage('待处理')), findsOneWidget);
      expect(find.text('建议复核 2'), findsNothing);
      expect(find.text('已复核'), findsOneWidget);
      expect(find.textContaining('3 行已确认'), findsOneWidget);
      expect(find.textContaining('暂时没有建议复核的行'), findsOneWidget);

      await tester.tap(find.text(ReviewInboxScreen.undoLabel));
      await tester.pumpAndSettle();

      expect(repository.writes, 2);
      expect(find.text(ReviewInboxScreen.undoneMessage), findsOneWidget);
      expect(find.text('建议复核 2'), findsOneWidget);
      expect(find.textContaining('0 行已确认'), findsOneWidget);
    });

    testWidgets('别处刚保存过时不覆盖，提示再试', (tester) async {
      repository = _FakeProjectRepository([pendingProject()]);
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      repository.conflictNext = true;
      await chooseMarkAll(tester, 'p');
      await tester.tap(confirmButton());
      await tester.pumpAndSettle();

      expect(repository.writes, 0);
      expect(
        find.text(ReviewInboxScreen.conflictMessage('待处理')),
        findsOneWidget,
      );
      expect(find.text(ReviewInboxScreen.undoLabel), findsNothing);
      expect(find.text('建议复核 2'), findsOneWidget);
    });
  });

  group('全部工程标为已复核', () {
    final markEverything = find.byKey(ReviewInboxSummaryBar.buttonKey);

    ProjectManifest pendingProject(String id, String name, int count) {
      return _project(
        id: id,
        name: name,
        lines: [
          for (var index = 0; index < count; index++)
            _line('第 ${index + 1} 行', confidence: 20, startSeconds: index * 4),
        ],
      );
    }

    List<ProjectManifest> twoPending() => [
      pendingProject('a', '甲', 2),
      pendingProject('b', '乙', 3),
    ];

    Finder confirmButton() => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(
        FilledButton,
        ReviewInboxGlobalReviewText.confirmLabel,
      ),
    );

    Future<void> confirmMarkEverything(WidgetTester tester) async {
      await tester.tap(markEverything);
      await tester.pumpAndSettle();
      await tester.tap(confirmButton());
    }

    testWidgets('只在还有待复核的工程时出现', (tester) async {
      repository = _FakeProjectRepository([
        _project(id: 'done', name: '已完成', lines: [_line('星星')]),
      ]);
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      expect(markEverything, findsNothing);

      repository.projects.add(pendingProject('p', '待处理', 1));
      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(markEverything, findsOneWidget);
      expect(
        find.text(ReviewInboxGlobalReviewText.buttonLabel),
        findsOneWidget,
      );
    });

    testWidgets('确认前说明涉及哪些工程、多少行', (tester) async {
      repository = _FakeProjectRepository(twoPending());
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(markEverything);
      await tester.pumpAndSettle();

      expect(find.text('把 2 个工程全部标为已复核？'), findsOneWidget);
      expect(
        find.textContaining('这 2 个工程共 5 行都会记为人工确认，建议复核的 5 行会移出列表。'),
        findsOneWidget,
      );
      expect(find.text('「乙」「甲」'), findsOneWidget);
      expect(find.textContaining('完成后可以撤销'), findsOneWidget);
    });

    testWidgets('取消时什么都不写', (tester) async {
      repository = _FakeProjectRepository(twoPending());
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(markEverything);
      await tester.pumpAndSettle();
      await tester.tap(find.text(ReviewInboxGlobalReviewText.cancelLabel));
      await tester.pumpAndSettle();

      expect(repository.writes, 0);
      expect(find.textContaining('共 5 行建议复核'), findsOneWidget);
    });

    testWidgets('确认后所有工程离开队列，并可以一次撤销', (tester) async {
      repository = _FakeProjectRepository(twoPending());
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await confirmMarkEverything(tester);
      await tester.pumpAndSettle();

      expect(repository.writes, 2);
      expect(find.text('已将 2 个工程标为已复核（新确认 5 行）'), findsOneWidget);
      expect(find.textContaining('暂时没有建议复核的行'), findsOneWidget);
      expect(find.text('已复核'), findsNWidgets(2));
      expect(markEverything, findsNothing);

      await tester.tap(find.text(ReviewInboxGlobalReviewText.undoLabel));
      await tester.pumpAndSettle();

      expect(repository.writes, 4);
      expect(find.text('已撤销，2 个工程的复核标记恢复原样'), findsOneWidget);
      expect(find.textContaining('共 5 行建议复核'), findsOneWidget);
    });

    testWidgets('别处刚保存过的工程被跳过，其余照常保存', (tester) async {
      repository = _FakeProjectRepository(twoPending());
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      repository.conflictNext = true;
      await confirmMarkEverything(tester);
      await tester.pumpAndSettle();

      expect(repository.writes, 1);
      expect(
        find.text(
          '已将 1 个工程标为已复核（新确认 2 行）；'
          '1 个工程刚在别处保存过，已跳过并重新读取，请再试一次',
        ),
        findsOneWidget,
      );
      expect(find.text(ReviewInboxGlobalReviewText.undoLabel), findsOneWidget);
    });

    testWidgets('运行时显示进度，单个工程的菜单暂不可用', (tester) async {
      repository = _FakeProjectRepository(twoPending());
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      repository.gate = Completer<void>();
      await confirmMarkEverything(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(ReviewInboxSummaryBar.progressKey), findsOneWidget);
      expect(find.text('正在标记第 0/2 个工程…'), findsOneWidget);
      expect(markEverything, findsNothing);
      final menus = tester.widgetList<PopupMenuButton<VoidCallback>>(
        find.byType(PopupMenuButton<VoidCallback>),
      );
      expect(menus, isNotEmpty);
      expect(menus.every((menu) => !menu.enabled), isTrue);

      repository.gate!.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(ReviewInboxSummaryBar.progressKey), findsNothing);
      expect(repository.writes, 2);
    });
  });

  group('读屏', () {
    Semantics tileOf(WidgetTester tester, String name) =>
        tester.widget<Semantics>(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.hint == ReviewInboxScreen.openEditorHint &&
                (widget.properties.label ?? '').startsWith('$name，'),
          ),
        );

    test('一行读成一句：名称、副标题和徽标', () {
      expect(
        ReviewInboxScreen.tileLabel(
          name: '晴天',
          subtitle: '周杰伦 · 32 行 · 20 行已确认',
          pending: 12,
          mustCheck: 5,
          unscored: 0,
          reasons: '主要原因：双引擎分歧 7、置信度低 5',
        ),
        '晴天，周杰伦，32 行，20 行已确认，建议复核 12 行，必看 5 行，'
        '主要原因：双引擎分歧 7、置信度低 5',
      );
    });

    test('全部复核完时只说已复核', () {
      expect(
        ReviewInboxScreen.tileLabel(
          name: '七里香',
          subtitle: '8 行 · 8 行已确认',
          pending: 0,
          mustCheck: 0,
          unscored: 3,
          reasons: '主要原因：空歌词 1',
        ),
        '七里香，8 行，8 行已确认，已复核',
      );
    });

    test('未评分只在还有建议复核时说，保存中也说出来', () {
      expect(
        ReviewInboxScreen.tileLabel(
          name: '稻香',
          subtitle: '10 行 · 0 行已确认',
          pending: 4,
          mustCheck: 0,
          unscored: 10,
          saving: true,
        ),
        '稻香，10 行，0 行已确认，建议复核 4 行，未评分 10 行，'
        '${ReviewInboxScreen.savingLabel}',
      );
    });

    testWidgets('一行是一个按钮，点按进入编辑器', (tester) async {
      final handle = tester.ensureSemantics();
      repository = _FakeProjectRepository([
        _project(id: 'abc', name: '月亮代表我的心', lines: [_line('月亮')]),
      ]);
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      final tile = tileOf(tester, '月亮代表我的心');
      expect(tile.properties.label, '月亮代表我的心，1 行，0 行已确认，已复核');
      expect(tile.properties.button, isTrue);
      expect(find.bySemanticsLabel(tile.properties.label!), findsOneWidget);
      // The name and badge are no longer separate stops.
      expect(find.bySemanticsLabel('月亮代表我的心'), findsNothing);
      // Nothing to mark, so no action.
      expect(tile.properties.customSemanticsActions, isNull);

      tile.properties.onTap!();
      await tester.pumpAndSettle();
      expect(pushedRoutes, ['/project/abc/lyrics']);
      handle.dispose();
    });

    testWidgets('全部标为已复核是这一行的读屏操作', (tester) async {
      repository = _FakeProjectRepository([
        _project(
          id: 'p',
          name: '待处理',
          lines: [
            _line('第 1 行', confidence: 20),
            _line('第 2 行', confidence: 30, startSeconds: 4),
            _line('第 3 行', startSeconds: 8),
          ],
        ),
      ]);
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      final tile = tileOf(tester, '待处理');
      expect(tile.properties.label, contains('建议复核 2 行'));
      final actions = tile.properties.customSemanticsActions!;
      expect(actions.keys.map((action) => action.label), [
        ReviewInboxScreen.markAllReviewedLabel,
      ]);

      actions.values.single();
      await tester.pumpAndSettle();
      // The same confirmation as the menu entry.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('「待处理」的 3 行都会记为人工确认'), findsOneWidget);
      expect(repository.writes, 0);
    });
  });
}
