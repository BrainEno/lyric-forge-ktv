import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/routes.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_queue_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/batch_transcription_queue.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/widgets/global_transcription_queue_bar.dart';

// The desktop background-transcription bar as a screen reader meets it
// (audit A-04): one button that says what is running and opens the import
// page, with pause and resume as its actions.

TranscriptionQueueItem _item(
  String id,
  TranscriptionQueueItemStatus status, {
  double progress = 0,
  String message = '',
}) => TranscriptionQueueItem(
  id: id,
  sourcePath: '/music/$id.mp3',
  projectName: '歌曲 $id',
  status: status,
  progress: progress,
  message: message,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Future<void> _pump(WidgetTester tester, _FakeQueue queue, List<String> routes) {
  return tester.pumpWidget(
    MaterialApp(
      onGenerateRoute: (settings) {
        routes.add(settings.name ?? '');
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => settings.name == '/'
              ? Scaffold(
                  bottomNavigationBar: GlobalTranscriptionQueueBar(
                    queue: queue,
                  ),
                )
              : const Scaffold(body: Text('导入页')),
        );
      },
    ),
  );
}

Semantics _bar(WidgetTester tester) => tester.widget<Semantics>(
  find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        widget.properties.hint == GlobalTranscriptionQueueBar.openHint,
  ),
);

void main() {
  group('wording', () {
    test('running, with the song in focus and the count', () {
      expect(
        GlobalTranscriptionQueueBar.semanticsLabel(
          paused: false,
          projectName: '晴天',
          failed: 0,
          done: 1,
          total: 3,
        ),
        '正在后台解析，晴天，已完成 1 / 3 首',
      );
    });

    test('paused, with failures', () {
      expect(
        GlobalTranscriptionQueueBar.semanticsLabel(
          paused: true,
          projectName: '七里香',
          failed: 2,
          done: 0,
          total: 4,
        ),
        '后台解析已暂停，七里香，2 首失败，已完成 0 / 4 首',
      );
    });

    test('the running song says its step and percent (D-049)', () {
      expect(
        GlobalTranscriptionQueueBar.focusDetail(
          _item(
            'a',
            TranscriptionQueueItemStatus.running,
            progress: 0.47,
            message: '第 3/6 步 · 识别歌词：Qwen3-ASR 识别中',
          ),
        ),
        '47% · 第 3/6 步 · 识别歌词：Qwen3-ASR 识别中',
      );
      expect(
        GlobalTranscriptionQueueBar.focusDetail(
          _item('a', TranscriptionQueueItemStatus.running, progress: 0.1),
        ),
        '10%',
      );
      expect(
        GlobalTranscriptionQueueBar.focusDetail(
          _item('a', TranscriptionQueueItemStatus.queued, message: '排队中'),
        ),
        isNull,
      );
    });

    test('progress is a clamped percentage', () {
      expect(GlobalTranscriptionQueueBar.progressValue(0.333), '33%');
      expect(GlobalTranscriptionQueueBar.progressValue(1.2), '100%');
      expect(GlobalTranscriptionQueueBar.progressValue(-1), '0%');
    });
  });

  group('bar', () {
    // Set inside each test and cleared before it ends: the binding checks
    // foundation debug variables before tear-downs run.
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    testWidgets('is one button that opens the import page', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final handle = tester.ensureSemantics();
      final queue = _FakeQueue(
        TranscriptionQueueSnapshot(
          items: [
            _item('a', TranscriptionQueueItemStatus.completed),
            _item('b', TranscriptionQueueItemStatus.running, progress: 0.5),
            _item('c', TranscriptionQueueItemStatus.queued),
            _item('d', TranscriptionQueueItemStatus.queued),
          ],
          isPaused: false,
          isProcessing: true,
        ),
      );
      final routes = <String>[];
      await _pump(tester, queue, routes);

      expect(find.byKey(const ValueKey('queue_bar_detail')), findsOneWidget);
      const label = '正在后台解析，歌曲 b，已完成 1 / 4 首';
      expect(find.bySemanticsLabel(label), findsOneWidget);
      // The pieces are not separate stops.
      expect(find.bySemanticsLabel('歌曲 b'), findsNothing);

      final bar = _bar(tester);
      expect(bar.properties.label, label);
      expect(bar.properties.button, isTrue);
      // (1 done + 0.5 of the running one) of 4.
      expect(bar.properties.value, '38%');

      bar.properties.onTap!();
      await tester.pumpAndSettle();
      expect(routes.last, Routes.import);
      expect(find.text('导入页'), findsOneWidget);

      handle.dispose();
      await queue.close();
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('pause is an action while the queue runs', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final queue = _FakeQueue(
        TranscriptionQueueSnapshot(
          items: [_item('a', TranscriptionQueueItemStatus.running)],
          isPaused: false,
          isProcessing: true,
        ),
      );
      await _pump(tester, queue, <String>[]);

      final actions = _bar(tester).properties.customSemanticsActions!;
      expect(actions.keys.map((action) => action.label), [
        GlobalTranscriptionQueueBar.pauseLabel,
      ]);
      actions[const CustomSemanticsAction(
        label: GlobalTranscriptionQueueBar.pauseLabel,
      )]!();
      expect(queue.calls, ['pause']);
      // The button keeps the same name.
      expect(
        find.byTooltip(GlobalTranscriptionQueueBar.pauseLabel),
        findsOneWidget,
      );

      await queue.close();
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('resume is an action once the queue has stopped', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final queue = _FakeQueue(
        TranscriptionQueueSnapshot(
          items: [_item('a', TranscriptionQueueItemStatus.paused)],
          isPaused: true,
          isProcessing: false,
        ),
      );
      await _pump(tester, queue, <String>[]);

      final bar = _bar(tester);
      expect(bar.properties.label, startsWith('后台解析已暂停'));
      final actions = bar.properties.customSemanticsActions!;
      expect(actions.keys.map((action) => action.label), [
        GlobalTranscriptionQueueBar.resumeLabel,
      ]);
      actions.values.single();
      expect(queue.calls, ['resume']);

      await queue.close();
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('no action while a pause is still being saved', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final queue = _FakeQueue(
        TranscriptionQueueSnapshot(
          items: [_item('a', TranscriptionQueueItemStatus.running)],
          isPaused: true,
          isProcessing: true,
        ),
      );
      await _pump(tester, queue, <String>[]);

      expect(_bar(tester).properties.customSemanticsActions, isNull);
      expect(find.byTooltip('正在保存进度'), findsOneWidget);

      await queue.close();
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('failures are said, not only coloured', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final queue = _FakeQueue(
        TranscriptionQueueSnapshot(
          items: [
            _item('a', TranscriptionQueueItemStatus.failed),
            _item('b', TranscriptionQueueItemStatus.queued),
          ],
          isPaused: true,
          isProcessing: false,
        ),
      );
      await _pump(tester, queue, <String>[]);

      expect(_bar(tester).properties.label, contains('1 首失败'));

      await queue.close();
      debugDefaultTargetPlatformOverride = null;
    });
  });
}

class _FakeQueue implements BatchTranscriptionQueue {
  _FakeQueue(this.current);

  @override
  final TranscriptionQueueSnapshot current;
  final _controller = StreamController<TranscriptionQueueSnapshot>.broadcast();
  final calls = <String>[];

  @override
  Stream<TranscriptionQueueSnapshot> get snapshots => _controller.stream;

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  Future<void> close() => _controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
