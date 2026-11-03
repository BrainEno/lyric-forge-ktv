import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_collection_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/playback_queue_panel.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  testWidgets('uses the supplied session snapshot without subscribing again', (
    tester,
  ) async {
    final session = _UnsubscribableSession();
    final state = PlaybackSessionState(
      queue: [
        PlaybackItem(
          id: 'track-1',
          title: '当前歌曲',
          audioAsset: const AudioAsset(
            originalPath: '/music/track.wav',
            format: 'wav',
          ),
        ),
      ],
      currentIndex: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackQueuePanel(
            session: session,
            sessionState: state,
            collectionRepository: _UnusedCollectionRepository(),
          ),
        ),
      ),
    );

    expect(find.text('当前歌曲'), findsOneWidget);
    expect(find.text('1 首 · 待播 0 首'), findsOneWidget);
    expect(find.byTooltip('开启随机播放'), findsOneWidget);
  });
}

class _UnsubscribableSession implements PlaybackSessionService {
  @override
  Stream<PlaybackSessionState> get stateStream =>
      throw StateError('the provided snapshot should avoid another subscription');

  @override
  PlaybackSessionState get currentState =>
      throw StateError('the provided snapshot should avoid another read');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedCollectionRepository implements LocalMediaCollectionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
