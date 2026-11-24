import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The music catalogs share one grid card and one cover (audit L-04, T-03).
// The local library's artist/album, song and playlist grids and the phone's
// view of the desktop library each drew their own card around a private
// artwork wrapper, with different corners, paddings, title weights and grid
// ratios. These checks keep a screen from growing its own copy again.

const _catalogScreens = <String>[
  'lib/features/player/presentation/screens/local_library_explorer_screen.dart',
  'lib/features/player/presentation/screens/local_artist_album_browser_screen.dart',
  'lib/features/player/presentation/widgets/local_collection_widgets.dart',
  'lib/features/transfer/presentation/screens/mobile_remote_grouped_library_screen.dart',
];

const _libraryScreens = <String>[
  ..._catalogScreens,
  'lib/features/transfer/presentation/screens/mobile_remote_music_library_screen.dart',
];

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('catalog grids', () {
    for (final path in _catalogScreens) {
      final name = path.split('/').last;

      test('$name draws its grid cards with AppCatalogCard', () {
        final source = _read(path);
        expect(source, contains("core/widgets/app_catalog_card.dart'"));
        expect(source, contains('AppCatalogCard('));
      });

      test('$name lays its grid out with the shared delegate', () {
        final source = _read(path);
        expect(source, contains('AppCatalogCard.gridDelegateFor('));
        expect(
          source,
          isNot(contains('SliverGridDelegateWithFixedCrossAxisCount(')),
          reason: 'columns, ratio and spacing come from AppCatalogCard.',
        );
      });
    }
  });

  group('covers', () {
    // The wrappers that only chose a radius and an icon.
    final wrapper = RegExp(r'class _\w*Artwork\b');

    for (final path in _libraryScreens) {
      final name = path.split('/').last;

      test('$name has no private artwork wrapper', () {
        expect(wrapper.hasMatch(_read(path)), isFalse);
      });
    }

    test('the remote cover reuses the shared placeholder', () {
      final source = _read(
        'lib/features/transfer/presentation/widgets/remote_media_artwork.dart',
      );
      expect(source, contains('AppArtworkPlaceholder('));
      expect(source, contains('AppArtwork('));
      expect(source, isNot(contains('class _Fallback')));
      // The fetch stays its own: bytes over the pinned channel, never a URL
      // that would carry the token.
      expect(source, contains('widget.client.fetchArtwork(widget.track)'));
      expect(source, isNot(contains('Image.network(')));
      expect(source, isNot(contains('remoteUri:')));
    });

    test('artists are round everywhere through AppArtwork.person', () {
      final source = _read(
        'lib/features/player/presentation/screens/'
        'local_artist_album_browser_screen.dart',
      );
      expect(source, contains('AppArtwork.person('));
      expect(source, isNot(contains('Icons.person_rounded')));
    });

    test('a missing song uses AppArtwork.missing', () {
      final source = _read(
        'lib/features/player/presentation/screens/'
        'local_library_explorer_screen.dart',
      );
      expect(source, contains('AppArtwork.missing('));
      expect(source, isNot(contains('placeholderColor:')));
    });

    test('library covers use the named radii', () {
      for (final path in _catalogScreens) {
        final source = _read(path);
        final covers = RegExp(
          r'AppArtwork\((?:[^()]|\([^()]*\))*\)',
        ).allMatches(source);
        for (final cover in covers) {
          final text = cover.group(0)!;
          if (!text.contains('borderRadius:')) continue;
          expect(
            text,
            matches(
              RegExp(r'borderRadius: AppArtwork\.(tileRadius|rowRadius)'),
            ),
            reason: '$path: $text',
          );
        }
      }
    });
  });

  group('cards', () {
    test('a card is drawn on its Material so the ripple shows', () {
      final source = _read('lib/core/widgets/app_catalog_card.dart');
      final material = source.indexOf('child: Material(');
      final ink = source.indexOf('child: InkWell(');
      expect(material, greaterThan(0));
      expect(ink, greaterThan(material));
      expect(source, isNot(contains('BoxDecoration(')));
    });

    test('the grid cards no longer paint their own surface', () {
      for (final path in _catalogScreens) {
        final source = _read(path);
        for (final name in [
          'class _CatalogCard ',
          'class _ExplorerCard ',
          'class _PlaylistCard ',
          'class LocalPlaylistCard ',
          'class _CatalogGroupCard ',
        ]) {
          final start = source.indexOf(name);
          if (start < 0) continue;
          final next = source.indexOf('\nclass ', start + 1);
          final body = source.substring(start, next < 0 ? source.length : next);
          expect(
            body,
            isNot(contains('BoxDecoration(')),
            reason: '$path ${name.trim()}',
          );
          expect(
            body,
            contains('AppCatalogCard('),
            reason: '$path ${name.trim()}',
          );
        }
      }
    });
  });
}
