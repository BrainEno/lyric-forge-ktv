import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/core/widgets/app_artwork.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_hub_connection.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/remote_audio_track.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/services/media_hub_client_service.dart';
import 'package:lyric_forge_ktv/features/transfer/presentation/widgets/remote_media_artwork.dart';

// RemoteMediaArtwork draws a desktop cover on the phone with the frame and
// placeholder of AppArtwork (audit T-03), so the same song looks the same in
// both libraries. Only the fetch is its own: bytes over the pinned channel.

const _track = RemoteAudioTrack(
  id: 'track-1',
  title: '晴天',
  format: 'flac',
  byteLength: 1024,
  streamPath: '/stream/track-1',
  downloadPath: '/download/track-1',
  hasArtwork: true,
  artworkPath: '/artwork/track-1',
);

const _connection = MediaHubConnection(
  host: '10.0.0.8',
  port: 8844,
  token: 'token',
);

class _FakeClient implements MediaHubClientService {
  _FakeClient({this.connection = _connection});

  MediaHubConnection? connection;
  final requests = <String>[];
  Completer<List<int>> artwork = Completer<List<int>>();

  @override
  MediaHubConnection? get currentConnection => connection;

  @override
  bool get isConnected => connection != null;

  @override
  Future<List<int>> fetchArtwork(RemoteAudioTrack track) {
    requests.add(track.id);
    return artwork.future;
  }

  @override
  Future<MediaHubConnection> connect(Uri pairingUri) async => _connection;

  @override
  Future<void> connectTo(MediaHubConnection connection) async {
    this.connection = connection;
  }

  @override
  Future<void> disconnect() async {
    connection = null;
  }

  @override
  Future<List<RemoteAudioTrack>> fetchTracks() async => const [_track];

  @override
  Uri playbackUriFor(RemoteAudioTrack track) =>
      Uri.parse('https://10.0.0.8:8844${track.streamPath}');

  @override
  Future<LyricDocument?> fetchLyrics(RemoteAudioTrack track) async => null;

  @override
  Future<void> downloadTrack({
    required RemoteAudioTrack track,
    required String destinationPath,
    TransferProgressCallback? onProgress,
  }) async {}

  @override
  Future<void> uploadFile({
    required String sourcePath,
    String? remoteFileName,
    TransferProgressCallback? onProgress,
  }) async {}

  @override
  Future<void> dispose() async {}
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

Finder _inArtwork(Type type) => find.descendant(
  of: find.byType(RemoteMediaArtwork),
  matching: find.byType(type),
);

void main() {
  testWidgets('without a cover it shows the shared placeholder', (
    tester,
  ) async {
    final client = _FakeClient(connection: null);
    await _pump(
      tester,
      RemoteMediaArtwork(
        track: _track,
        client: client,
        extent: 52,
        fallbackIcon: Icons.person_rounded,
      ),
    );

    expect(client.requests, isEmpty);
    expect(_inArtwork(AppArtworkPlaceholder), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.person_rounded));
    expect(icon.size, closeTo(52 * AppArtwork.placeholderIconScale, 0.01));
    expect(icon.color, AppColors.textTertiary);
    expect(tester.getSize(find.byType(RemoteMediaArtwork)), const Size(52, 52));
  });

  testWidgets('a track without artwork is never fetched', (tester) async {
    final client = _FakeClient();
    await _pump(
      tester,
      RemoteMediaArtwork(
        track: const RemoteAudioTrack(
          id: 'track-2',
          title: '七里香',
          format: 'mp3',
          byteLength: 10,
          streamPath: '/stream/track-2',
          downloadPath: '/download/track-2',
        ),
        client: client,
        extent: 40,
      ),
    );

    expect(client.requests, isEmpty);
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
  });

  testWidgets('list rows default to the row radius', (tester) async {
    await _pump(
      tester,
      RemoteMediaArtwork(
        track: _track,
        client: _FakeClient(connection: null),
        extent: 46,
      ),
    );

    final clip = tester.widget<ClipRRect>(_inArtwork(ClipRRect));
    expect(clip.borderRadius, BorderRadius.circular(AppArtwork.rowRadius));
  });

  testWidgets('cards can pass the tile radius and fill their cell', (
    tester,
  ) async {
    await _pump(
      tester,
      SizedBox(
        width: 150,
        height: 150,
        child: RemoteMediaArtwork(
          track: _track,
          client: _FakeClient(connection: null),
          borderRadius: AppArtwork.tileRadius,
        ),
      ),
    );

    final clip = tester.widget<ClipRRect>(_inArtwork(ClipRRect));
    expect(clip.borderRadius, BorderRadius.circular(AppArtwork.tileRadius));
    expect(
      tester.getSize(find.byType(RemoteMediaArtwork)),
      const Size(150, 150),
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.music_note_rounded));
    expect(icon.size, closeTo(150 * AppArtwork.placeholderIconScale, 0.01));
  });

  testWidgets('while fetching it shows the placeholder under a spinner', (
    tester,
  ) async {
    final client = _FakeClient();
    await _pump(
      tester,
      RemoteMediaArtwork(track: _track, client: client, extent: 52),
    );

    expect(client.requests, ['track-1']);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(_inArtwork(AppArtworkPlaceholder), findsOneWidget);
  });

  testWidgets('fetched bytes are drawn from memory', (tester) async {
    final client = _FakeClient();
    await _pump(
      tester,
      RemoteMediaArtwork(track: _track, client: client, extent: 52),
    );

    client.artwork.complete(const [137, 80, 78, 71, 13, 10, 26, 10]);
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failed or empty fetch falls back to the placeholder', (
    tester,
  ) async {
    final client = _FakeClient();
    await _pump(
      tester,
      RemoteMediaArtwork(track: _track, client: client, extent: 52),
    );
    client.artwork.completeError(const SocketException('offline'));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_inArtwork(AppArtworkPlaceholder), findsOneWidget);

    final empty = _FakeClient();
    await _pump(
      tester,
      RemoteMediaArtwork(
        key: const ValueKey('empty'),
        track: _track,
        client: empty,
        extent: 52,
      ),
    );
    empty.artwork.complete(const <int>[]);
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(_inArtwork(AppArtworkPlaceholder), findsOneWidget);
  });

  testWidgets('a downloaded cover is shown from disk without a fetch', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('remote_artwork_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final cover = File('${dir.path}${Platform.pathSeparator}cover.png')
      ..writeAsBytesSync(const [0]);
    final client = _FakeClient();

    await _pump(
      tester,
      RemoteMediaArtwork(
        track: _track,
        client: client,
        localPath: cover.path,
        extent: 52,
      ),
    );

    expect(client.requests, isEmpty);
    expect(find.byType(AppArtwork), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<FileImage>());
  });

  testWidgets('a missing local copy falls back to the fetch', (tester) async {
    final client = _FakeClient();
    await _pump(
      tester,
      RemoteMediaArtwork(
        track: _track,
        client: client,
        localPath: '/no/such/cover.png',
        extent: 52,
      ),
    );

    expect(client.requests, ['track-1']);
    expect(find.byType(AppArtwork), findsNothing);
  });

  testWidgets('artists can be round, as in the local library', (tester) async {
    await _pump(
      tester,
      RemoteMediaArtwork(
        track: _track,
        client: _FakeClient(connection: null),
        extent: 80,
        fallbackIcon: Icons.person_rounded,
        circle: true,
      ),
    );

    expect(_inArtwork(ClipOval), findsOneWidget);
    expect(_inArtwork(ClipRRect), findsNothing);
    expect(tester.getSize(_inArtwork(ClipOval)), const Size(80, 80));
  });

  testWidgets('a round downloaded cover stays round', (tester) async {
    final dir = Directory.systemTemp.createTempSync('remote_artwork_round');
    addTearDown(() => dir.deleteSync(recursive: true));
    final cover = File('${dir.path}${Platform.pathSeparator}artist.png')
      ..writeAsBytesSync(const [0]);

    await _pump(
      tester,
      RemoteMediaArtwork(
        track: _track,
        client: _FakeClient(),
        localPath: cover.path,
        extent: 80,
        circle: true,
      ),
    );

    expect(_inArtwork(ClipOval), findsOneWidget);
    expect(_inArtwork(ClipRRect), findsNothing);
  });
}
