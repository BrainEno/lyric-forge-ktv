import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Covers go through AppArtwork (audit C-04).
///
/// The audit found twelve cover widgets with their own placeholder, and four
/// of them still drew a bare `Image.file`, which paints a broken image when
/// the file exists but cannot be decoded. AppArtwork owns local and network
/// covers; the remote library widget, which fetches bytes over the pinned
/// channel, is the one other place that builds an image, and every image it
/// builds needs an error fallback.
void main() {
  const shared = 'lib/core/widgets/app_artwork.dart';
  const remote =
      'lib/features/transfer/presentation/widgets/remote_media_artwork.dart';
  final imageCall = RegExp(r'Image\.(file|network|memory)\(');

  test('only the shared cover and the remote cover build images', () {
    final owners = <String>{for (final hit in _imageCalls(imageCall)) hit.path};
    expect(owners, {shared, remote});
  });

  test('every image outside AppArtwork has an error fallback', () {
    final missing = [
      for (final hit in _imageCalls(imageCall))
        if (hit.path != shared && !hit.call.contains('errorBuilder:'))
          '${hit.path}:${hit.line}',
    ];
    expect(
      missing,
      isEmpty,
      reason:
          'Use AppArtwork, or give the image an errorBuilder that shows '
          'the placeholder.',
    );
  });

  test('the converged screens use AppArtwork', () {
    const screens = [
      // The project player's cover moved into its transport widget.
      'lib/features/player/presentation/widgets/project_player_transport.dart',
      'lib/features/project/presentation/screens/project_detail_screen.dart',
      'lib/features/player/presentation/widgets/'
          'local_media_metadata_dialog.dart',
      'lib/features/transfer/presentation/screens/'
          'mobile_download_manager_screen.dart',
      'lib/features/home/presentation/widgets/dashboard_shelves.dart',
    ];
    for (final path in screens) {
      final source = File(path).readAsStringSync();
      expect(source, contains('AppArtwork('), reason: path);
      expect(source, isNot(contains('Image.file(')), reason: path);
    }
  });

  test('the scanner sees the whole call, not just its first line', () {
    const source = '''
child: Image.file(
  file,
  errorBuilder: (_, _, _) => const SizedBox(),
),
''';
    final hit = _callsIn('x.dart', source, imageCall).single;
    expect(hit.line, 1);
    expect(hit.call, contains('errorBuilder:'));
  });
}

class _ImageCall {
  const _ImageCall(this.path, this.line, this.call);

  final String path;
  final int line;

  /// Source text from `Image.x(` to its closing parenthesis.
  final String call;
}

List<_ImageCall> _imageCalls(RegExp pattern) => [
  for (final file in Directory('lib').listSync(recursive: true))
    if (file is File && file.path.endsWith('.dart'))
      ..._callsIn(
        file.path.replaceAll(r'\', '/'),
        file.readAsStringSync(),
        pattern,
      ),
];

List<_ImageCall> _callsIn(String path, String source, RegExp pattern) {
  final calls = <_ImageCall>[];
  for (final match in pattern.allMatches(source)) {
    final lineStart = source.lastIndexOf('\n', match.start) + 1;
    if (source.substring(lineStart, match.start).trimLeft().startsWith('//')) {
      continue;
    }
    var depth = 0;
    var end = match.end - 1;
    for (; end < source.length; end++) {
      final char = source[end];
      if (char == '(') depth++;
      if (char == ')' && --depth == 0) break;
    }
    final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
    calls.add(_ImageCall(path, line, source.substring(match.start, end + 1)));
  }
  return calls;
}
