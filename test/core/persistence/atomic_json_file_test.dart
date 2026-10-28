import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/persistence/atomic_json_file.dart';

bool _isCounterDocument(Object? value) =>
    value is Map && value['counter'] is int;

String _document(int counter) => jsonEncode({'counter': counter});

void main() {
  group('AtomicJsonFile', () {
    late Directory root;
    late File destination;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('atomic-json-file-');
      destination = File('${root.path}${Platform.pathSeparator}state.json');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('keeps the previous valid document when replacement fails', () async {
      await destination.writeAsString(_document(1), flush: true);

      await expectLater(
        AtomicJsonFile.write(
          destination,
          _document(2),
          validate: _isCounterDocument,
          onStage: (stage) async {
            if (stage == AtomicJsonWriteStage.canonicalRemoved) {
              throw StateError('injected replacement failure');
            }
          },
        ),
        throwsA(isA<StateError>()),
      );

      expect(jsonDecode(await destination.readAsString()), {'counter': 1});
      expect(
        jsonDecode(await AtomicJsonFile.backupFor(destination).readAsString()),
        {'counter': 1},
      );
      expect(await destination.exists(), isTrue);
    });

    test(
      'restores a flushed temporary document when canonical is missing',
      () async {
        await AtomicJsonFile.temporaryFor(
          destination,
        ).writeAsString(_document(3), flush: true);

        final result = await AtomicJsonFile.recoverIfNeeded(
          destination,
          validate: _isCounterDocument,
        );

        expect(result, AtomicJsonRecoveryResult.restoredFromTemporary);
        expect(jsonDecode(await destination.readAsString()), {'counter': 3});
      },
    );

    test(
      'restores the last valid backup when canonical and temp are invalid',
      () async {
        await destination.writeAsString('{broken');
        await AtomicJsonFile.temporaryFor(
          destination,
        ).writeAsString('{also broken');
        await AtomicJsonFile.backupFor(
          destination,
        ).writeAsString(_document(4), flush: true);

        final result = await AtomicJsonFile.recoverIfNeeded(
          destination,
          validate: _isCounterDocument,
        );

        expect(result, AtomicJsonRecoveryResult.restoredFromBackup);
        expect(jsonDecode(await destination.readAsString()), {'counter': 4});
      },
    );

    test(
      'does not overwrite an invalid store without a valid recovery copy',
      () async {
        await destination.writeAsString('{manual recovery may be needed');

        await expectLater(
          AtomicJsonFile.write(
            destination,
            _document(5),
            validate: _isCounterDocument,
          ),
          throwsA(isA<FileSystemException>()),
        );

        expect(
          await destination.readAsString(),
          '{manual recovery may be needed',
        );
      },
    );

    test(
      'keeps the previous document as a backup after a successful update',
      () async {
        await AtomicJsonFile.write(
          destination,
          _document(1),
          validate: _isCounterDocument,
        );
        await AtomicJsonFile.write(
          destination,
          _document(2),
          validate: _isCounterDocument,
        );

        expect(jsonDecode(await destination.readAsString()), {'counter': 2});
        expect(
          jsonDecode(
            await AtomicJsonFile.backupFor(destination).readAsString(),
          ),
          {'counter': 1},
        );
      },
    );
  });
}
