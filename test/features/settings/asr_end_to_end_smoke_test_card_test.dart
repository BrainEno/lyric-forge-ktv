import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/app_destinations.dart';
import 'package:lyric_forge_ktv/features/settings/presentation/widgets/asr_end_to_end_smoke_test_card.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_end_to_end_smoke_test_service.dart';

class _FakeSmokeTestService implements AsrEndToEndSmokeTestService {
  final progress = StreamController<AsrEndToEndSmokeProgress>.broadcast();
  final runs = <String>[];
  Completer<AsrEndToEndSmokeResult>? pending;
  int cancels = 0;

  @override
  Stream<AsrEndToEndSmokeProgress> get progressStream => progress.stream;

  @override
  bool get isRunning => pending != null && !pending!.isCompleted;

  @override
  Future<AsrEndToEndSmokeResult> run(String audioPath) {
    runs.add(audioPath);
    pending = Completer<AsrEndToEndSmokeResult>();
    return pending!.future;
  }

  @override
  Future<void> cancel() async => cancels++;
}

const _result = AsrEndToEndSmokeResult(
  projectId: 'p1',
  projectName: '晴天 · 试识别',
  sourcePath: '/music/晴天.mp3',
  lyricLineCount: 42,
  environmentInstalled: true,
);

void main() {
  late _FakeSmokeTestService service;
  late List<String> routes;

  setUp(() {
    service = _FakeSmokeTestService();
    routes = <String>[];
  });

  tearDown(() => service.progress.close());

  Widget host({required bool desktop, String? pickedPath = '/music/晴天.mp3'}) {
    return MaterialApp(
      onGenerateRoute: (settings) {
        routes.add(settings.name ?? '');
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const Scaffold(body: Text('校对页')),
        );
      },
      home: Scaffold(
        body: SingleChildScrollView(
          child: AsrEndToEndSmokeTestCard(
            smokeTestService: service,
            desktopSupported: desktop,
            pickAudio: () async => pickedPath,
          ),
        ),
      ),
    );
  }

  testWidgets('speaks to users, not developers', (tester) async {
    await tester.pumpWidget(host(desktop: true));

    expect(find.text('试识别一首歌'), findsOneWidget);
    expect(find.text('选择歌曲开始试识别'), findsOneWidget);
    for (final jargon in ['ASR', 'runtime', '端到端', '自检']) {
      expect(find.textContaining(jargon), findsNothing, reason: jargon);
    }
  });

  testWidgets('is disabled with a reason outside Windows and macOS', (
    tester,
  ) async {
    await tester.pumpWidget(host(desktop: false));

    expect(find.textContaining('只能在 Windows 和 macOS'), findsOneWidget);
    final button = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('选择歌曲开始试识别'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('runs the picked song, reports progress and opens the editor', (
    tester,
  ) async {
    await tester.pumpWidget(host(desktop: true));

    await tester.tap(find.text('选择歌曲开始试识别'));
    await tester.pump();
    await tester.pump();
    expect(service.runs, ['/music/晴天.mp3']);
    expect(find.text('正在准备试识别'), findsOneWidget);
    expect(find.text('取消试识别'), findsOneWidget);

    service.progress.add(
      const AsrEndToEndSmokeProgress(
        stage: AsrEndToEndSmokeStage.transcribing,
        progress: 0.5,
        message: '正在识别歌词',
      ),
    );
    await tester.pump();
    expect(find.text('正在识别歌词'), findsOneWidget);

    await tester.tap(find.text('取消试识别'));
    await tester.pump();
    expect(service.cancels, 1);

    service.pending!.complete(_result);
    await tester.pumpAndSettle();

    expect(routes, ['/project/p1/lyrics']);
    expect(find.text('校对页'), findsOneWidget);
  });

  testWidgets('keeps a summary of the last run', (tester) async {
    await tester.pumpWidget(host(desktop: true));

    await tester.tap(find.text('选择歌曲开始试识别'));
    await tester.pump();
    await tester.pump();
    service.pending!.complete(_result);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('校对页'))).pop();
    await tester.pumpAndSettle();

    expect(find.text(lastRunSummary(_result)), findsOneWidget);
    expect(find.text('取消试识别'), findsNothing);
  });

  testWidgets('shows a plain failure message', (tester) async {
    await tester.pumpWidget(host(desktop: true));

    await tester.tap(find.text('选择歌曲开始试识别'));
    await tester.pump();
    await tester.pump();
    service.pending!.completeError(StateError('磁盘已满'));
    await tester.pumpAndSettle();

    expect(find.textContaining('试识别失败'), findsOneWidget);
    expect(find.textContaining('磁盘已满'), findsOneWidget);
    expect(routes, isEmpty);
  });

  testWidgets('does nothing when the picker is cancelled', (tester) async {
    await tester.pumpWidget(host(desktop: true, pickedPath: null));

    await tester.tap(find.text('选择歌曲开始试识别'));
    await tester.pumpAndSettle();

    expect(service.runs, isEmpty);
    expect(find.text('取消试识别'), findsNothing);
  });

  testWidgets('explains an empty path instead of failing silently', (
    tester,
  ) async {
    await tester.pumpWidget(host(desktop: true, pickedPath: ' '));

    await tester.tap(find.text('选择歌曲开始试识别'));
    await tester.pumpAndSettle();

    expect(service.runs, isEmpty);
    expect(find.text('没有取得所选歌曲的文件路径'), findsOneWidget);
  });

  test('settings groups put troubleshooting after recognition', () {
    final screen = File(
      'lib/features/settings/presentation/screens/settings_screen.dart',
    ).readAsStringSync();
    final recognition = screen.indexOf("label: 'AI 识别'");
    final troubleshooting = screen.indexOf("label: '故障排查'");
    final diagnostics = screen.indexOf('DiagnosticsSettingsCard(');
    final trialRun = screen.indexOf('AsrEndToEndSmokeTestCard(');

    expect(recognition, greaterThan(0));
    expect(troubleshooting, greaterThan(recognition));
    expect(diagnostics, greaterThan(troubleshooting));
    expect(trialRun, greaterThan(diagnostics));
  });

  test('the settings tooltip only promises what the page holds', () {
    final description = AppDestination.settings.description;
    expect(description, isNot(contains('播放')));
    expect(description, isNot(contains('存储')));
    expect(description, contains('识别'));
  });
}
