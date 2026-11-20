import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/core/theme/spacing_tokens.dart';
import 'package:lyric_forge_ktv/core/widgets/app_artwork.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

Finder _inArtwork(Type type) =>
    find.descendant(of: find.byType(AppArtwork), matching: find.byType(type));

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

  testWidgets('a status colour can mark a meaningful placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const AppArtwork(
          size: 48,
          placeholderIcon: Icons.link_off_rounded,
          placeholderColor: AppColors.error,
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.link_off_rounded));
    expect(icon.color, AppColors.error);
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

  // The project player, project detail, metadata dialog and download list
  // used a bare Image.file, which paints a broken image for a cover that
  // exists but cannot be decoded. They now use AppArtwork (audit C-04).
  testWidgets('a cover file that cannot be decoded shows the placeholder', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('app_artwork_broken');
    addTearDown(() => dir.deleteSync(recursive: true));
    final cover = File('${dir.path}${Platform.pathSeparator}broken.jpg')
      ..writeAsBytesSync(const [1, 2, 3, 4, 5, 6, 7, 8]);
    final placeholder = find.byIcon(Icons.album_rounded);

    await tester.runAsync(() async {
      await tester.pumpWidget(_host(AppArtwork(path: cover.path, size: 80)));
      expect(find.byType(Image), findsOneWidget);
      for (var i = 0; i < 40 && placeholder.evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pump();

    expect(placeholder, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // The library sections each wrapped AppArtwork in a private widget that
  // only picked a radius and an icon (audit L-04). The choices are named
  // here so every section draws the same cover for the same kind of thing.
  group('library roles', () {
    test('tiles and rows have one radius each', () {
      expect(AppArtwork.tileRadius, AppSpacing.radiusLarge);
      expect(AppArtwork.rowRadius, AppSpacing.radiusMedium);
      expect(AppArtwork.rowRadius, lessThan(AppArtwork.tileRadius));
    });

    testWidgets('an artist is a circle with a person placeholder', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const AppArtwork.person(size: 96)));

      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
      expect(_inArtwork(ClipOval), findsOneWidget);
      expect(_inArtwork(ClipRRect), findsNothing);
      expect(tester.getSize(find.byType(AppArtwork)), const Size.square(96));
      final icon = tester.widget<Icon>(find.byIcon(Icons.person_rounded));
      expect(icon.color, AppColors.textTertiary);
    });

    testWidgets('a circle in a wide cell stays round and centred', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 200,
            height: 120,
            child: AppArtwork.person(),
          ),
        ),
      );

      final oval = tester.getRect(_inArtwork(ClipOval));
      expect(oval.size, const Size.square(120));
      final cell = tester.getRect(find.byType(AppArtwork));
      expect(oval.center, cell.center);
      final icon = tester.widget<Icon>(find.byIcon(Icons.person_rounded));
      expect(icon.size, closeTo(120 * AppArtwork.placeholderIconScale, 0.01));
    });

    testWidgets('a missing song shows the broken link in the error colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const AppArtwork.missing(path: '/no/such/cover.jpg', size: 64)),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.link_off_rounded));
      expect(icon.color, AppColors.error);
      expect(find.byIcon(Icons.album_rounded), findsNothing);
      final clip = tester.widget<ClipRRect>(_inArtwork(ClipRRect));
      expect(clip.borderRadius, BorderRadius.circular(AppArtwork.tileRadius));
    });

    testWidgets('a missing song keeps its cover while the file is on disk', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('app_artwork_missing');
      addTearDown(() => dir.deleteSync(recursive: true));
      final cover = File('${dir.path}${Platform.pathSeparator}cover.png')
        ..writeAsBytesSync(const [0]);

      await tester.pumpWidget(
        _host(AppArtwork.missing(path: cover.path, size: 64)),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<FileImage>());
      expect(find.byIcon(Icons.link_off_rounded), findsNothing);
    });

    testWidgets('a missing song in a list row takes the row radius', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const AppArtwork.missing(size: 44, borderRadius: AppArtwork.rowRadius),
        ),
      );

      final clip = tester.widget<ClipRRect>(_inArtwork(ClipRRect));
      expect(clip.borderRadius, BorderRadius.circular(AppArtwork.rowRadius));
    });
  });

  group('AppArtworkPlaceholder', () {
    testWidgets('matches the placeholder AppArtwork draws', (tester) async {
      await tester.pumpWidget(
        _host(
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppArtwork(size: 50, placeholderIcon: Icons.cloud_rounded),
              AppArtworkPlaceholder(icon: Icons.cloud_rounded, size: 50),
            ],
          ),
        ),
      );

      final icons = tester
          .widgetList<Icon>(find.byIcon(Icons.cloud_rounded))
          .toList();
      expect(icons, hasLength(2));
      expect(icons.first.size, icons.last.size);
      expect(icons.first.color, icons.last.color);
      final boxes = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(Row),
              matching: find.byType(ColoredBox),
            ),
          )
          .map((box) => box.color)
          .toSet();
      expect(boxes, {AppColors.bgSurface});
    });

    testWidgets('without a size it scales the icon to the short side', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 90,
            height: 300,
            child: AppArtworkPlaceholder(icon: Icons.person_rounded),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.person_rounded));
      expect(icon.size, closeTo(90 * AppArtwork.placeholderIconScale, 0.01));
      expect(icon.color, AppColors.textTertiary);
    });

    testWidgets('takes a status colour', (tester) async {
      await tester.pumpWidget(
        _host(
          const AppArtworkPlaceholder(
            icon: Icons.link_off_rounded,
            color: AppColors.error,
            size: 40,
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.link_off_rounded));
      expect(icon.color, AppColors.error);
    });
  });
}
