import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/widgets/app_artwork.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('existingFile', () {
    test('returns the file only when the trimmed path exists', () {
      final dir = Directory.systemTemp.createTempSync('app_artwork_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final cover = File('${dir.path}${Platform.pathSeparator}cover.jpg')
        ..writeAsBytesSync(const [0]);

      expect(AppArtwork.existingFile(' ${cover.path} ')?.path, cover.path);
      expect(AppArtwork.existingFile('${cover.path}.missing'), isNull);
      expect(AppArtwork.existingFile('   '), isNull);
      expect(AppArtwork.existingFile(null), isNull);
    });
  });

  test('networkUri accepts only http and https', () {
    final https = Uri.parse('https://example.com/a.jpg');
    expect(AppArtwork.networkUri(https), https);
    expect(AppArtwork.networkUri(Uri.parse('http://lan/a.jpg')), isNotNull);
    expect(AppArtwork.networkUri(Uri.parse('file:///tmp/a.jpg')), isNull);
    expect(AppArtwork.networkUri(null), isNull);
  });

  testWidgets('without a cover it shows the scaled placeholder icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AppArtwork(
          path: '/no/such/cover.jpg',
          remoteUri: Uri.parse('file:///tmp/a.jpg'),
          size: 100,
        ),
      ),
    );

    expect(find.byType(Image), findsNothing);
    final icon = tester.widget<Icon>(find.byIcon(Icons.album_rounded));
    expect(icon.size, closeTo(100 * AppArtwork.placeholderIconScale, 0.01));
    expect(tester.getSize(find.byType(AppArtwork)), const Size.square(100));
  });

  testWidgets('without a size it fills the parent', (tester) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 200,
          height: 160,
          child: AppArtwork(placeholderIcon: Icons.cloud_rounded),
        ),
      ),
    );

    expect(tester.getSize(find.byType(AppArtwork)), const Size(200, 160));
    final icon = tester.widget<Icon>(find.byIcon(Icons.cloud_rounded));
    expect(icon.size, closeTo(160 * AppArtwork.placeholderIconScale, 0.01));
  });

  testWidgets('a remote cover is requested over the network', (tester) async {
    await tester.pumpWidget(
      _host(
        AppArtwork(
          remoteUri: Uri.parse('https://example.com/cover.jpg'),
          size: 48,
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<NetworkImage>());
    expect((image.image as NetworkImage).url, 'https://example.com/cover.jpg');
  });
}
