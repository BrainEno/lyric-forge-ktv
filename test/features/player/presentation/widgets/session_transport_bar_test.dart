import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/session_transport_bar.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/transport_bar.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

PlaybackItem _song(String id) => PlaybackItem(
  id: id,
  title: id,
  audioAsset: AudioAsset(originalPath: '/music/$id.mp3', format: 'mp3'),
);

class _FakeSession implements PlaybackSessionService {
  _FakeSession(this.state);

  PlaybackSessionState state;
  final List<String> calls = [];

  @override
  PlaybackSessionState get currentState => state;

  @override
  Future<void> togglePlayPause() async => calls.add('toggle');

  @override
  Future<void> skipNext() async => calls.add('next');

  @override
  Future<void> skipPrevious() async => calls.add('previous');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

IconButton _button(WidgetTester tester, String tooltip) {
  return tester.widget<IconButton>(
    find.ancestor(
      of: find.byTooltip(tooltip),
      matching: find.byType(IconButton),
    ),
  );
}

void main() {
  const idle = PlaybackState.idle();

  testWidgets('drives the session from the buttons', (tester) async {
    final session = _FakeSession(
      PlaybackSessionState(queue: [_song('a'), _song('b')], currentIndex: 0),
    );
    await _pump(tester, SessionTransportBar(session: session, playback: idle));

    await tester.tap(find.byTooltip(TransportBar.previousTooltip));
    await tester.tap(find.byTooltip(TransportBar.playTooltip));
    await tester.tap(find.byTooltip(TransportBar.nextTooltip));

    expect(session.calls, ['previous', 'toggle', 'next']);
  });

  testWidgets('next is disabled on the last song', (tester) async {
    final session = _FakeSession(
      PlaybackSessionState(queue: [_song('a'), _song('b')], currentIndex: 1),
    );
    await _pump(tester, SessionTransportBar(session: session, playback: idle));

    expect(_button(tester, TransportBar.nextTooltip).onPressed, isNull);
    expect(_button(tester, TransportBar.previousTooltip).onPressed, isNotNull);
  });

  testWidgets('both skips are disabled with nothing queued', (tester) async {
    final session = _FakeSession(const PlaybackSessionState());
    await _pump(tester, SessionTransportBar(session: session, playback: idle));

    expect(_button(tester, TransportBar.nextTooltip).onPressed, isNull);
    expect(_button(tester, TransportBar.previousTooltip).onPressed, isNull);
  });

  testWidgets('a queue snapshot wins over the session state', (tester) async {
    final session = _FakeSession(const PlaybackSessionState());
    await _pump(
      tester,
      SessionTransportBar(
        session: session,
        playback: idle,
        queue: PlaybackSessionState(
          queue: [_song('a'), _song('b')],
          currentIndex: 0,
        ),
      ),
    );

    expect(_button(tester, TransportBar.nextTooltip).onPressed, isNotNull);
  });

  testWidgets('shows pause while playing', (tester) async {
    final session = _FakeSession(const PlaybackSessionState());
    await _pump(
      tester,
      SessionTransportBar(
        session: session,
        playback: idle.copyWith(isPlaying: true),
      ),
    );

    expect(find.byTooltip(TransportBar.pauseTooltip), findsOneWidget);
    expect(find.byTooltip(TransportBar.playTooltip), findsNothing);
  });

  test('loading and buffering count as busy', () {
    expect(SessionTransportBar.isBusy(idle), isFalse);
    expect(SessionTransportBar.isBusy(idle.copyWith(isLoading: true)), isTrue);
    expect(
      SessionTransportBar.isBusy(idle.copyWith(isBuffering: true)),
      isTrue,
    );
  });

  testWidgets('seek buttons appear only when wired', (tester) async {
    final session = _FakeSession(const PlaybackSessionState());
    var back = 0;
    var forward = 0;
    await _pump(
      tester,
      SessionTransportBar(
        session: session,
        playback: idle,
        onSeekBack: () => back++,
        onSeekForward: () => forward++,
      ),
    );

    await tester.tap(find.byTooltip(TransportBar.seekBackTooltip));
    await tester.tap(find.byTooltip(TransportBar.seekForwardTooltip));
    expect((back, forward), (1, 1));
  });
}
