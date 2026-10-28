import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transfer/data/services/http_media_hub_service.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/shared_audio_track.dart';

void main() {
  late Directory temp;
  late HttpMediaHubService service;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('elysium-media-hub-artwork-');
    service = HttpMediaHubService();
  });

  tearDown(() async {
    await service.stopSharing();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('track catalog exposes authenticated artwork endpoint', () async {
    final audio = File('${temp.path}${Platform.pathSeparator}song.mp3');
    final artwork = File('${temp.path}${Platform.pathSeparator}cover.png');
    await audio.writeAsBytes(const [1, 2, 3, 4, 5]);
    final artworkBytes = <int>[137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3, 4];
    await artwork.writeAsBytes(artworkBytes);

    final session = await service.startSharing([
      SharedAudioTrack(
        id: 'track-1',
        title: 'Song',
        localPath: audio.path,
        artworkPath: artwork.path,
        format: 'mp3',
        byteLength: await audio.length(),
      ),
    ]);

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final base = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: session.port,
    );

    final tracksRequest = await client.getUrl(
      base.replace(path: '/v1/tracks', queryParameters: {'token': session.token}),
    );
    final tracksResponse = await tracksRequest.close();
    final decoded = jsonDecode(await utf8.decoder.bind(tracksResponse).join())
        as Map<String, dynamic>;
    final tracks = decoded['tracks'] as List<dynamic>;
    final track = Map<String, dynamic>.from(tracks.single as Map);

    expect(track['hasArtwork'], isTrue);
    expect(track['artworkPath'], '/v1/tracks/track-1/artwork');

    final artworkRequest = await client.getUrl(
      base.replace(
        path: track['artworkPath'] as String,
        queryParameters: {'token': session.token},
      ),
    );
    final artworkResponse = await artworkRequest.close();
    final received = await artworkResponse.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );

    expect(artworkResponse.statusCode, HttpStatus.ok);
    expect(artworkResponse.headers.contentType?.mimeType, 'image/png');
    expect(received, artworkBytes);
  });

  test('artwork endpoint rejects missing token', () async {
    final audio = File('${temp.path}${Platform.pathSeparator}song.mp3');
    final artwork = File('${temp.path}${Platform.pathSeparator}cover.jpg');
    await audio.writeAsBytes(const [1, 2, 3]);
    await artwork.writeAsBytes(const [1, 2, 3]);

    final session = await service.startSharing([
      SharedAudioTrack(
        id: 'secure-track',
        title: 'Secure',
        localPath: audio.path,
        artworkPath: artwork.path,
        format: 'mp3',
        byteLength: await audio.length(),
      ),
    ]);

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(
      Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: session.port,
        path: '/v1/tracks/secure-track/artwork',
      ),
    );
    final response = await request.close();
    await response.drain<void>();

    expect(response.statusCode, HttpStatus.unauthorized);
  });
}
