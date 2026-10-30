import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Documentation reference contracts', () {
    test('opencode instructions point at existing files', () async {
      final config = await File('opencode.jsonc').readAsString();
      final instructions = RegExp(
        r'"instructions"\s*:\s*\[([^\]]*)\]',
      ).firstMatch(config);
      expect(instructions, isNotNull);
      final paths = RegExp(
        r'"([^"]+)"',
      ).allMatches(instructions!.group(1)!).map((m) => m.group(1)!).toList();
      expect(paths, isNotEmpty);
      for (final path in paths) {
        expect(
          await File(path).exists(),
          isTrue,
          reason: 'opencode.jsonc instructions entry must exist: $path',
        );
      }
    });

    test('player architecture doc names the implemented stack', () async {
      final doc = await File('docs/architecture_player.md').readAsString();
      // Superseded proposal pieces must not return as if implemented.
      expect(doc, isNot(contains('HivePlayHistoryRepository')));
      expect(doc, isNot(contains('ProjectTransferService')));
      expect(doc, isNot(contains('shelf:')));
      expect(doc, contains('HttpMediaHubService'));
      expect(doc, contains('AtomicJsonFile'));
    });

    test('D-002 records the pinned flutter_soloud version', () async {
      final pubspec = await File('pubspec.yaml').readAsString();
      final pin = RegExp(
        r'^  flutter_soloud: (.+)$',
        multiLine: true,
      ).firstMatch(pubspec);
      expect(pin, isNotNull);
      final decisions = await File('docs/decisions.md').readAsString();
      final d002 = decisions.substring(
        decisions.indexOf('## D-002'),
        decisions.indexOf('## D-003'),
      );
      expect(d002, contains('flutter_soloud ${pin!.group(1)!.trim()}'));
    });
  });
}
