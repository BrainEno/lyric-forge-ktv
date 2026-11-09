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

    test(
      'separation is described as a goal, not a shipped capability',
      () async {
        final readme = await File('README.md').readAsString();
        final prd = await File('docs/prd.md').readAsString();
        expect(
          readme,
          contains('cannot generate separated vocal/accompaniment tracks'),
        );
        expect(readme, contains('import external stems through its UI'));
        expect(readme, contains('the referenced file must be accessible'));
        expect(prd, contains('当前版本尚未实现人声/伴奏分离'));
        expect(prd, contains('不能通过界面导入外部分离音轨'));
        expect(prd, contains('分离仍是桌面端待完成的产品目标'));
        expect(prd, contains('7.1 桌面端必须有'));
      },
    );

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
