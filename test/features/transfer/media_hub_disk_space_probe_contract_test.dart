import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transfer/data/services/http_media_hub_service.dart';

void main() {
  group('Media Hub Windows disk-space probe script', () {
    test('matches the pinned PowerShell content', () {
      // Pin the exact script: any drift (including accidental non-PowerShell
      // text pasted into the literal) must fail here first. Issue #255
      // shipped Dart class definitions inside this string, which broke
      // every Windows incoming upload with a 507 response.
      expect(
        mediaHubWindowsDiskSpaceProbeScript,
        r'''
$path = $env:LYRICFORGE_UPLOAD_PATH
$root = [System.IO.Path]::GetPathRoot($path)
if ($root -notmatch '^[A-Za-z]:\\$') { exit 3 }
$drive = New-Object System.IO.DriveInfo -ArgumentList $root
[Console]::Out.Write([string]$drive.AvailableFreeSpace)''',
      );
    });

    test('contains no Dart source fragments', () {
      for (final fragment in <String>[
        'class ',
        'final List<',
        'HttpServer',
        '@override',
      ]) {
        expect(
          mediaHubWindowsDiskSpaceProbeScript,
          isNot(contains(fragment)),
          reason: 'Probe script must stay pure PowerShell: $fragment',
        );
      }
      expect(
        mediaHubWindowsDiskSpaceProbeScript,
        contains('[System.IO.Path]::GetPathRoot'),
      );
      expect(
        mediaHubWindowsDiskSpaceProbeScript,
        contains('AvailableFreeSpace'),
      );
      expect(mediaHubWindowsDiskSpaceProbeScript, contains('{ exit 3 }'));
    });

    test('media hub service defines each helper class once', () async {
      final source = await File(
        'lib/features/transfer/data/services/http_media_hub_service.dart',
      ).readAsString();
      for (final name in <String>[
        '_BoundMediaHubServers',
        'MediaHubException',
        '_ByteRange',
        '_ParsedRange',
      ]) {
        final definitions = RegExp(
          '^class $name[ {]',
          multiLine: true,
        ).allMatches(source).length;
        expect(
          definitions,
          1,
          reason: '$name must be defined exactly once in the service file',
        );
      }
    });

    test(
      'prints a non-negative byte count under real PowerShell',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'lyricforge-probe-',
        );
        addTearDown(() async {
          if (await temp.exists()) {
            await temp.delete(recursive: true);
          }
        });

        final result = await Process.run(
          'powershell.exe',
          [
            '-NoLogo',
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            mediaHubWindowsDiskSpaceProbeScript,
          ],
          environment: {'LYRICFORGE_UPLOAD_PATH': temp.absolute.path},
        );

        expect(result.exitCode, 0, reason: 'stderr: ${result.stderr}');
        final freeBytes = int.tryParse(result.stdout.toString().trim());
        expect(freeBytes, isNotNull);
        expect(freeBytes, greaterThanOrEqualTo(0));
      },
      skip: Platform.isWindows ? false : 'Requires Windows PowerShell',
    );
  });
}
