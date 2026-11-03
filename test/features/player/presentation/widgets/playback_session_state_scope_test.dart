import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/playback_session_state_scope.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  testWidgets('provides the current session and forwards later updates', (
    tester,
  ) async {
    final session = _FakePlaybackSession();
    await tester.pumpWidget(
      MaterialApp(
        home: PlaybackSessionStateScope(
          session: session,
          child: Builder(
            builder: (context) {
              final queuedCount = context.select<
                PlaybackSessionState,
                int
              >((state) => state.queue.length);
              return Text('$queuedCount');
            },
          ),
        ),
      ),
    );

    expect(find.text('0'), findsOneWidget);

    session.emit(
      PlaybackSessionState(
        queue: [
          PlaybackItem(
            id: 'one',
            title: 'One',
            audioAsset: const AudioAsset(originalPath: '/one.wav', format: 'wav'),
          ),
        ],
        currentIndex: 0,
      ),
    );
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await session.close();
  });
}

class _FakePlaybackSession implements PlaybackSessionService {
  final StreamController<PlaybackSessionState> _states =
      StreamController<PlaybackSessionState>.broadcast();
  PlaybackSessionState _currentState = const PlaybackSessionState();

  @override
  Stream<PlaybackSessionState> get stateStream => _states.stream;

  @override
  PlaybackSessionState get currentState => _currentState;

  void emit(PlaybackSessionState state) {
    _currentState = state;
    _states.add(state);
  }

  Future<void> close() => _states.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
