import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_asr_managed_storage_service.dart';

void main() {
  test('moves managed ASR tree to another parent and persists the root', () async {
    final sandbox = await Directory.systemTemp.createTemp('lyricforge-asr-root-');
    addTearDown(() => sandbox.delete(recursive: true));
    final support = Directory('${sandbox.path}${Platform.pathSeparator}support');
    final destination = Directory('${sandbox.path}${Platform.pathSeparator}models-drive');
    await support.create(recursive: true);
    await destination.create(recursive: true);

    final service = LocalAsrManagedStorageService(
      supportDirectoryResolver: () async => support,
    );
    final source = await service.resolveRoot();
    final model = File(
      '${source.path}${Platform.pathSeparator}models${Platform.pathSeparator}qwen${Platform.pathSeparator}model.bin',
    );
    await model.parent.create(recursive: true);
    await model.writeAsBytes(List<int>.generate(1024, (index) => index % 251));
    final part = File(
      '${source.path}${Platform.pathSeparator}downloads${Platform.pathSeparator}runtime.zip.part',
    );
    await part.parent.create(recursive: true);
    await part.writeAsBytes(List<int>.filled(333, 7));

    final progress = <int>[];
    final result = await service.moveToParent(
      destination.path,
      onProgress: (copied, total) => progress.add(copied),
    );

    final expected = Directory(
      '${destination.path}${Platform.pathSeparator}LyricForge${Platform.pathSeparator}ASRRuntime',
    ).absolute.path;
    expect(result.moved, isTrue);
    expect(result.targetRoot, expected);
    expect(result.copiedBytes, 1357);
    expect(result.copiedFiles, 2);
    expect(progress, isNotEmpty);
    expect(progress.last, 1357);
    expect(await File('$expected${Platform.pathSeparator}models${Platform.pathSeparator}qwen${Platform.pathSeparator}model.bin').length(), 1024);
    expect(await File('$expected${Platform.pathSeparator}downloads${Platform.pathSeparator}runtime.zip.part').length(), 333);
    expect((await service.resolveRoot()).path, expected);
    expect(await source.exists(), isFalse);
  });

  test('can migrate a custom root back to the default application-support root',
      () async {
    final sandbox = await Directory.systemTemp.createTemp('lyricforge-asr-default-');
    addTearDown(() => sandbox.delete(recursive: true));
    final support = Directory('${sandbox.path}${Platform.pathSeparator}support');
    final destination = Directory('${sandbox.path}${Platform.pathSeparator}external');
    await support.create(recursive: true);
    await destination.create(recursive: true);

    final service = LocalAsrManagedStorageService(
      supportDirectoryResolver: () async => support,
    );
    final source = await service.resolveRoot();
    final file = File('${source.path}${Platform.pathSeparator}bundle${Platform.pathSeparator}qwen3-asr');
    await file.parent.create(recursive: true);
    await file.writeAsString('runtime');

    await service.moveToParent(destination.path);
    final custom = await service.inspect();
    expect(custom.isDefault, isFalse);

    final back = await service.moveToDefault();
    final current = await service.inspect();

    expect(back.moved, isTrue);
    expect(current.isDefault, isTrue);
    expect(
      await File('${current.activeRoot}${Platform.pathSeparator}bundle${Platform.pathSeparator}qwen3-asr').readAsString(),
      'runtime',
    );
  });

  test('refuses to overwrite an existing LyricForge ASRRuntime tree', () async {
    final sandbox = await Directory.systemTemp.createTemp('lyricforge-asr-conflict-');
    addTearDown(() => sandbox.delete(recursive: true));
    final support = Directory('${sandbox.path}${Platform.pathSeparator}support');
    final destination = Directory('${sandbox.path}${Platform.pathSeparator}destination');
    await support.create(recursive: true);
    final service = LocalAsrManagedStorageService(
      supportDirectoryResolver: () async => support,
    );
    final source = await service.resolveRoot();
    await File('${source.path}${Platform.pathSeparator}source.bin').writeAsString('source');

    final conflicting = File(
      '${destination.path}${Platform.pathSeparator}LyricForge${Platform.pathSeparator}ASRRuntime${Platform.pathSeparator}foreign.bin',
    );
    await conflicting.parent.create(recursive: true);
    await conflicting.writeAsString('do not overwrite');

    await expectLater(
      service.moveToParent(destination.path),
      throwsA(isA<FileSystemException>()),
    );

    expect((await service.resolveRoot()).path, source.path);
    expect(await File('${source.path}${Platform.pathSeparator}source.bin').exists(), isTrue);
    expect(await conflicting.readAsString(), 'do not overwrite');
  });
}
