import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GitHub Actions CI workflow contracts', () {
    test('all workflows install the Flutter SDK through the shared pin', () async {
      final config = jsonDecode(await File('.fvmrc').readAsString());
      expect(config, isA<Map<String, dynamic>>());
      final flutterVersion = (config as Map<String, dynamic>)['flutter'];
      expect(flutterVersion, matches(RegExp(r'^\d+\.\d+\.\d+$')));

      final action = await File(
        '.github/actions/setup-flutter/action.yml',
      ).readAsString();
      expect(action, contains('with open(".fvmrc"'));
      expect(
        action,
        contains('flutter-version: \${{ steps.flutter-version.outputs.version }}'),
      );
      expect(action, contains('subosito/flutter-action@v2'));

      final directory = Directory('.github/workflows');
      final workflows = await directory
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.yml'))
          .cast<File>()
          .toList();
      expect(workflows, isNotEmpty);

      for (final file in workflows) {
        final source = await file.readAsString();
        expect(
          source,
          contains('./.github/actions/setup-flutter'),
          reason: '${file.path} must use the centrally pinned Flutter SDK',
        );
        expect(
          source,
          isNot(contains('subosito/flutter-action@v2')),
          reason: '${file.path} must not independently pin Flutter',
        );
      }
    });

    test('specialized workflows do not run the full suite independently', () async {
      final directory = Directory('.github/workflows');
      final workflows = await directory
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.yml'))
          .cast<File>()
          .toList();

      for (final file in workflows) {
        final source = await file.readAsString();
        expect(
          RegExp(r'^\s*-?\s*run:\s*flutter test\s*$', multiLine: true)
              .hasMatch(source),
          isFalse,
          reason: '${file.path} duplicates the universal full-suite gate',
        );
      }
    });

    test('KTV history validation owns recovery and interrupted WAV coverage', () async {
      final source = await File(
        '.github/workflows/ktv-history-validation.yml',
      ).readAsString();
      expect(source, contains('ktv_take_history_store_test.dart'));
      expect(source, contains('ktv_project_storage_test.dart'));
      expect(source, contains('pcm16_wav_recovery_test.dart'));
      expect(source, contains('pull_request:'));
      expect(source, contains('branches: [main]'));
    });

    test('stale KTV feature-branch-only trigger names are gone', () async {
      final directory = Directory('.github/workflows');
      final workflows = await directory
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.yml'))
          .cast<File>()
          .toList();

      const staleBranches = <String>[
        'fix/ktv-wav-interrupted-recovery',
        'fix/ktv-take-delete-path-safety',
        'feat/ktv-auto-recover-interrupted-takes',
      ];
      for (final file in workflows) {
        final source = await file.readAsString();
        for (final branch in staleBranches) {
          expect(
            source,
            isNot(contains(branch)),
            reason: '${file.path} must not depend on deleted feature branches',
          );
        }
      }
      expect(
        await File('.github/workflows/ktv-wav-recovery-validation.yml').exists(),
        isFalse,
      );
      expect(
        await File('.github/workflows/ktv-delete-safety-validation.yml').exists(),
        isFalse,
      );
      expect(
        await File('.github/workflows/ktv-auto-recovery-validation.yml').exists(),
        isFalse,
      );
    });
  });
}
