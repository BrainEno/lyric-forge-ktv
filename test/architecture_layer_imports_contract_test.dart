import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Layering ratchet for the feature architecture rules in AGENTS.md (#232):
/// domain must not import Flutter UI or platform APIs, repository contracts
/// live in domain while implementations live in data, and presentation must
/// not reach data implementations directly.
///
/// The baselines below freeze the violations that existed when the ratchet
/// was introduced. The ratchet only tightens: a new violation fails here
/// until the import itself is fixed (never baseline a new violation), and a
/// fixed violation fails here until its stale baseline entry is deleted.
/// The domain platform baseline reached zero when the playback lyrics
/// path handling moved behind `AudioPathCanonicalizer`; the remaining
/// burn-down is the presentation->data imports.
const Set<String> _platformBaseline = <String>{};

const Set<String> _presentationBaseline = <String>{
  'lib/features/player/presentation/screens/player_screen.dart -> lib/features/player/data/services/ktv_take_history_store.dart',
  'lib/features/transfer/presentation/screens/desktop_media_transfer_hub_v2_screen.dart -> lib/features/transfer/data/services/local_library_media_share_catalog.dart',
};

final RegExp _importPattern = RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''');
final RegExp _layerPattern = RegExp(
  r'^lib/features/[^/]+/(domain|data|presentation)/',
);

String? _layerOf(String path) => _layerPattern.firstMatch(path)?.group(1);

String _resolve(String uri, String importer) {
  const packagePrefix = 'package:lyric_forge_ktv/';
  if (uri.startsWith(packagePrefix)) {
    return 'lib/${uri.substring(packagePrefix.length)}';
  }
  if (uri.startsWith('dart:') || uri.startsWith('package:')) return uri;
  final parts = importer.split('/')..removeLast();
  for (final segment in uri.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(segment);
    }
  }
  return parts.join('/');
}

void _expectRatchet(Set<String> actual, Set<String> baseline) {
  final added = actual.difference(baseline).toList()..sort();
  final fixed = baseline.difference(actual).toList()..sort();
  expect(
    added,
    isEmpty,
    reason:
        'New layering violations (fix the import; the #232 baseline '
        'must only shrink):\n${added.join('\n')}',
  );
  expect(
    fixed,
    isEmpty,
    reason:
        'Stale baseline entries (these violations are fixed; delete '
        'them so the ratchet only tightens):\n${fixed.join('\n')}',
  );
}

void main() {
  group('Architecture layer import contracts', () {
    var scannedFiles = 0;
    final domainPlatform = <String>{};
    final domainLayer = <String>{};
    final presentationData = <String>{};
    final dataPresentation = <String>{};

    setUpAll(() async {
      final files = Directory('lib/features')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();
      scannedFiles = files.length;
      for (final file in files) {
        final importer = file.path.replaceAll('\\', '/');
        final layer = _layerOf(importer);
        if (layer == null) continue;
        for (final line in await file.readAsLines()) {
          final match = _importPattern.firstMatch(line);
          if (match == null) continue;
          final uri = match.group(1)!;
          final target = _resolve(uri, importer);
          final targetLayer = _layerOf(target);
          if (layer == 'domain' &&
              (uri.startsWith('dart:io') ||
                  uri.startsWith('dart:ffi') ||
                  uri.startsWith('package:flutter/'))) {
            domainPlatform.add('$importer -> $uri');
          }
          if (layer == 'domain' &&
              (targetLayer == 'data' || targetLayer == 'presentation')) {
            domainLayer.add('$importer -> $target');
          }
          if (layer == 'presentation' && targetLayer == 'data') {
            presentationData.add('$importer -> $target');
          }
          if (layer == 'data' && targetLayer == 'presentation') {
            dataPresentation.add('$importer -> $target');
          }
        }
      }
    });

    test('ratchet scans the feature tree', () {
      expect(
        scannedFiles,
        greaterThan(100),
        reason: 'Expected to scan the lib/features tree from the repo root.',
      );
    });

    test('domain does not import platform or Flutter APIs', () {
      _expectRatchet(domainPlatform, _platformBaseline);
    });

    test('domain does not import data or presentation layers', () {
      expect(
        domainLayer.toList()..sort(),
        isEmpty,
        reason: 'Domain must depend only on domain and core contracts.',
      );
    });

    test('presentation does not import data implementations', () {
      _expectRatchet(presentationData, _presentationBaseline);
    });

    test('data does not import the presentation layer', () {
      expect(
        dataPresentation.toList()..sort(),
        isEmpty,
        reason: 'Data implementations must not depend on UI code.',
      );
    });
  });
}
