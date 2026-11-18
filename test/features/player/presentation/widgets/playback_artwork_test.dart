import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/widgets/app_artwork.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/playback_artwork.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

PlaybackItem _item({
  String? artworkPath,
  String? thumbnailPath,
  Object? remoteArtwork,
  bool stream = false,
}) {
  return PlaybackItem(
    id: 'song',
    title: 'Song',
    artworkPath: artworkPath,
    streamUri: stream ? Uri.parse('http://127.0.0.1:9/stream') : null,
    audioAsset: AudioAsset(
      originalPath: '/music/song.mp3',
      format: 'mp3',
      thumbnailPath: thumbnailPath,
      metadata: {'remoteArtworkUri': ?remoteArtwork},
    ),
  );
}

void main() {
  test('the item cover wins over the audio thumbnail', () {
    expect(
      PlaybackArtwork.localPathOf(
        _item(artworkPath: ' /covers/a.jpg ', thumbnailPath: '/thumb.jpg'),
      ),
      '/covers/a.jpg',
    );
    expect(
      PlaybackArtwork.localPathOf(
        _item(artworkPath: '  ', thumbnailPath: '/thumb.jpg'),
      ),
      '/thumb.jpg',
    );
  });

  test('only Media Hub streams use a remote http(s) cover', () {
    const cover = 'https://hub.local/artwork/1.jpg';
    expect(
      PlaybackArtwork.remoteUriOf(_item(remoteArtwork: cover, stream: true)),
      Uri.parse(cover),
    );
    expect(PlaybackArtwork.remoteUriOf(_item(remoteArtwork: cover)), isNull);
    expect(
      PlaybackArtwork.remoteUriOf(
        _item(remoteArtwork: 'file:///tmp/1.jpg', stream: true),
      ),
      isNull,
    );
    expect(
      PlaybackArtwork.remoteUriOf(_item(remoteArtwork: 42, stream: true)),
      isNull,
    );
  });

  testWidgets('streams without a cover show the cloud placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PlaybackArtwork(item: _item(stream: true), size: 48),
        ),
      ),
    );

    expect(find.byType(AppArtwork), findsOneWidget);
    expect(find.byIcon(Icons.cloud_rounded), findsOneWidget);
    expect(find.byIcon(Icons.album_rounded), findsNothing);
  });
}
