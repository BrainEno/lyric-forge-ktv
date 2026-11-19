import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/global_playback_shortcuts.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

PlaybackItem _item(String id) => PlaybackItem(
  id: id,
  title: id,
  audioAsset: const AudioAsset(originalPath: '/music/a.mp3', format: 'mp3'),
);

class _FakeSession implements PlaybackSessionService {
  _FakeSession({this.queue = const [], this.position = Duration.zero});

  final List<PlaybackItem> queue;
  Duration position;
  final List<String> calls = [];

  @override
  PlaybackSessionState get currentState =>
      PlaybackSessionState(queue: queue, currentIndex: queue.isEmpty ? -1 : 0);

  @override
  PlaybackState get playbackState {
    const idle = PlaybackState.idle();
    return idle.copyWith(
      position: position,
      duration: const Duration(minutes: 3),
    );
  }

  @override
  Future<void> togglePlayPause() async => calls.add('toggle');

  @override
  Future<void> skipNext() async => calls.add('next');

  @override
  Future<void> skipPrevious() async => calls.add('previous');

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek ${position.inSeconds}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester,
  _FakeSession session, {
  FocusNode? buttonFocus,
}) {
  return tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          GlobalPlaybackShortcuts(playbackSession: session, child: child!),
      home: Scaffold(
        body: Column(
          children: [
            const TextField(),
            TextButton(
              focusNode: buttonFocus,
              onPressed: () => session.calls.add('button'),
              child: const Text('按钮'),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('space toggles playback while nothing is focused', (
    tester,
  ) async {
    final session = _FakeSession(queue: [_item('a'), _item('b')]);
    await _pump(tester, session);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(session.calls, ['toggle']);
  });

  testWidgets('space types into a focused text field', (tester) async {
    final session = _FakeSession(queue: [_item('a')]);
    await _pump(tester, session);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(session.calls, isEmpty);
  });

  testWidgets('space activates a focused button instead', (tester) async {
    final session = _FakeSession(queue: [_item('a')]);
    final buttonFocus = FocusNode();
    addTearDown(buttonFocus.dispose);
    await _pump(tester, session, buttonFocus: buttonFocus);

    buttonFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(session.calls, ['button']);
  });

  testWidgets('modifier arrows skip songs and seek', (tester) async {
    final session = _FakeSession(
      queue: [_item('a'), _item('b')],
      position: const Duration(seconds: 3),
    );
    await _pump(tester, session);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    // Seeking back from 0:03 stops at the start of the song.
    expect(session.calls, ['next', 'previous', 'seek 8', 'seek 0']);
  });

  testWidgets('keys pass through when nothing is queued', (tester) async {
    final session = _FakeSession();
    await _pump(tester, session);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(session.calls, isEmpty);
  });

  test('seeking forward stops at the end of the song', () {
    final session = _FakeSession(
      queue: [_item('a')],
      position: const Duration(minutes: 2, seconds: 58),
    );
    expect(
      GlobalPlaybackShortcuts.run(GlobalPlaybackCommand.seekForward, session),
      isTrue,
    );
    expect(session.calls, ['seek 180']);
  });

  test('next is unhandled on the last song', () {
    final session = _FakeSession(queue: [_item('a')]);
    expect(
      GlobalPlaybackShortcuts.run(GlobalPlaybackCommand.next, session),
      isFalse,
    );
    expect(session.calls, isEmpty);
  });

  test('hints name the keys for each platform', () {
    expect(
      GlobalPlaybackShortcuts.withHint(
        '暂停',
        GlobalPlaybackCommand.togglePlayPause,
      ),
      '暂停（空格）',
    );
    expect(
      GlobalPlaybackShortcuts.withHint(
        '下一首',
        GlobalPlaybackCommand.next,
        platform: TargetPlatform.windows,
      ),
      '下一首（Ctrl+→）',
    );
    expect(
      GlobalPlaybackShortcuts.withHint(
        '下一首',
        GlobalPlaybackCommand.next,
        platform: TargetPlatform.macOS,
      ),
      '下一首（⌘→）',
    );
  });
}
