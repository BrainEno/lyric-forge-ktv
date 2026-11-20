import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_collection_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/playback_queue_panel.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/playback_queue_semantics.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

// The queue panel's rows as a screen reader meets them (audit A-04): one
// button per song with its place in the queue, the reorderable list's move
// actions on the same stop, and the remove button as its own stop.

PlaybackItem _item(String id, String title, {String? artist}) => PlaybackItem(
  id: id,
  title: title,
  artist: artist,
  audioAsset: AudioAsset(originalPath: '/music/$id.mp3', format: 'mp3'),
);

final _state = PlaybackSessionState(
  queue: [
    _item('a', '晴天', artist: '周杰伦'),
    _item('b', '七里香'),
    _item('c', '稻香', artist: '周杰伦'),
  ],
  currentIndex: 0,
);

Future<_RecordingSession> _pump(WidgetTester tester) async {
  final session = _RecordingSession();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PlaybackQueuePanel(
          session: session,
          sessionState: _state,
          collectionRepository: _UnusedCollectionRepository(),
        ),
      ),
    ),
  );
  return session;
}

Semantics _labelled(WidgetTester tester, String label) =>
    tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == label,
      ),
    );

void main() {
  group('wording', () {
    test('a row says its place, title, source and whether it plays', () {
      expect(
        PlaybackQueueSemantics.row(
          position: 1,
          title: '晴天',
          source: '周杰伦',
          current: true,
        ),
        '第 1 首，晴天，周杰伦，正在播放',
      );
      expect(
        PlaybackQueueSemantics.row(
          position: 12,
          title: '七里香',
          source: '本地音乐',
          current: false,
        ),
        '第 12 首，七里香，本地音乐',
      );
    });

    test('a blank title still names the row', () {
      expect(
        PlaybackQueueSemantics.row(
          position: 2,
          title: '  ',
          source: '桌面音乐库',
          current: false,
        ),
        '第 2 首，未命名歌曲，桌面音乐库',
      );
    });

    test('removing the playing song says it skips ahead', () {
      expect(
        PlaybackQueueSemantics.removeTooltip(current: true),
        '从队列移除并播放下一首',
      );
      expect(PlaybackQueueSemantics.removeTooltip(current: false), '从队列移除');
    });
  });

  group('panel', () {
    testWidgets('each row is one labelled button', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      expect(find.bySemanticsLabel('第 1 首，晴天，周杰伦，正在播放'), findsOneWidget);
      expect(find.bySemanticsLabel('第 2 首，七里香，本地音乐'), findsOneWidget);
      expect(find.bySemanticsLabel('第 3 首，稻香，周杰伦'), findsOneWidget);
      // Title and source are not separate stops any more.
      expect(find.bySemanticsLabel('七里香'), findsNothing);

      final current = _labelled(tester, '第 1 首，晴天，周杰伦，正在播放');
      expect(current.properties.button, isTrue);
      expect(current.properties.selected, isTrue);
      expect(current.properties.hint, isNull);
      final next = _labelled(tester, '第 2 首，七里香，本地音乐');
      expect(next.properties.selected, isFalse);
      expect(next.properties.hint, PlaybackQueueSemantics.playHint);
      handle.dispose();
    });

    testWidgets('the semantic tap plays that row', (tester) async {
      final session = await _pump(tester);

      _labelled(tester, '第 2 首，七里香，本地音乐').properties.onTap!();
      await tester.pump();
      expect(session.played, [1]);

      await tester.tap(find.text('稻香'));
      await tester.pump();
      expect(session.played, [1, 2]);
    });

    testWidgets('a remove button removes without playing', (tester) async {
      final session = await _pump(tester);

      expect(find.byTooltip('从队列移除并播放下一首'), findsOneWidget);
      expect(find.byTooltip('从队列移除'), findsNWidgets(2));

      await tester.tap(find.byTooltip('从队列移除').last);
      await tester.pump();
      expect(session.removed, [2]);
      expect(session.played, isEmpty);
    });

    testWidgets('the move actions sit on the row node', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      final node = tester.getSemantics(find.bySemanticsLabel('第 2 首，七里香，本地音乐'));
      final data = node.getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.hasAction(SemanticsAction.customAction), isTrue);
      handle.dispose();
    });
  });
}

class _RecordingSession implements PlaybackSessionService {
  final played = <int>[];
  final removed = <int>[];

  @override
  Future<void> playAt(int index) async => played.add(index);

  @override
  Future<void> removeAt(int index) async => removed.add(index);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedCollectionRepository implements LocalMediaCollectionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
