import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_asr_managed_storage_service.dart';

void main() {
  test('moves managed ASR tree to another parent and persists the root', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'lyricforge-asr-root-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final support = Directory(
      '${sandbox.path}${Platform.pathSeparator}support',
    );
    final destination = Directory(
      '${sandbox.path}${Platform.pathSeparator}models-drive',
    );
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
    expect(
      await File(
        '$expected${Platform.pathSeparator}models${Platform.pathSeparator}qwen${Platform.pathSeparator}model.bin',
      ).length(),
      1024,
    );
    expect(
      await File(
        '$expected${Platform.pathSeparator}downloads${Platform.pathSeparator}runtime.zip.part',
      ).length(),
      333,
    );
    expect((await service.resolveRoot()).path, expected);
    expect(await source.exists(), isFalse);
  });

  test(
    'can migrate a custom root back to the default application-support root',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'lyricforge-asr-default-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final support = Directory(
        '${sandbox.path}${Platform.pathSeparator}support',
      );
      final destination = Directory(
        '${sandbox.path}${Platform.pathSeparator}external',
      );
      await support.create(recursive: true);
      await destination.create(recursive: true);

      final service = LocalAsrManagedStorageService(
        supportDirectoryResolver: () async => support,
      );
      final source = await service.resolveRoot();
      final file = File(
        '${source.path}${Platform.pathSeparator}bundle${Platform.pathSeparator}qwen3-asr',
      );
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
        await File(
          '${current.activeRoot}${Platform.pathSeparator}bundle${Platform.pathSeparator}qwen3-asr',
        ).readAsString(),
        'runtime',
      );
    },
  );

  test('refuses to overwrite an existing LyricForge ASRRuntime tree', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'lyricforge-asr-conflict-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final support = Directory(
      '${sandbox.path}${Platform.pathSeparator}support',
    );
    final destination = Directory(
      '${sandbox.path}${Platform.pathSeparator}destination',
    );
    await support.create(recursive: true);
    final service = LocalAsrManagedStorageService(
      supportDirectoryResolver: () async => support,
    );
    final source = await service.resolveRoot();
    await File(
      '${source.path}${Platform.pathSeparator}source.bin',
    ).writeAsString('source');

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
    expect(
      await File('${source.path}${Platform.pathSeparator}source.bin').exists(),
      isTrue,
    );
    expect(await conflicting.readAsString(), 'do not overwrite');
  });

  test(
    'adopts an existing ASRRuntime under the selected parent in place',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'lyricforge-asr-adopt-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final separator = Platform.pathSeparator;
      final support = Directory('${sandbox.path}${separator}support');
      final destination = Directory('${sandbox.path}${separator}drive-d');
      await support.create(recursive: true);
      await destination.create(recursive: true);

      final service = LocalAsrManagedStorageService(
        supportDirectoryResolver: () async => support,
      );
      final source = await service.resolveRoot();
      final sourceFile = File('${source.path}${separator}keep-current.bin');
      await sourceFile.writeAsString('current-root');

      final existingRoot = Directory(
        '${destination.path}${separator}LyricForge${separator}ASRRuntime',
      );
      final whisperModel = File(
        '${existingRoot.path}${separator}models${separator}whisper${separator}ggml-large-v3.bin',
      );
      await whisperModel.parent.create(recursive: true);
      await whisperModel.writeAsString('existing-whisper-model');
      final qwenMarker = File(
        '${existingRoot.path}${separator}models${separator}qwen${separator}Qwen--Qwen3-ASR-1.7B${separator}.lyricforge-model.json',
      );
      await qwenMarker.parent.create(recursive: true);
      await qwenMarker.writeAsString('{}');

      final result = await service.moveToParent(destination.path);

      expect(result.moved, isTrue);
      expect(result.adoptedExisting, isTrue);
      expect(result.oldRootRetained, isTrue);
      expect(result.copiedBytes, 0);
      expect(result.copiedFiles, 0);
      expect(result.targetRoot, existingRoot.absolute.path);
      expect((await service.resolveRoot()).path, existingRoot.absolute.path);
      expect(await sourceFile.readAsString(), 'current-root');
      expect(await whisperModel.readAsString(), 'existing-whisper-model');
      expect(await qwenMarker.exists(), isTrue);
    },
  );

  test(
    'adopts an ASRRuntime selected directly without nesting another root',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'lyricforge-asr-direct-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final separator = Platform.pathSeparator;
      final support = Directory('${sandbox.path}${separator}support');
      await support.create(recursive: true);

      final service = LocalAsrManagedStorageService(
        supportDirectoryResolver: () async => support,
      );
      final source = await service.resolveRoot();
      await File('${source.path}${separator}keep.bin').writeAsString('keep');

      final existingRoot = Directory(
        '${sandbox.path}${separator}downloaded${separator}ASRRuntime',
      );
      final runtime = File(
        '${existingRoot.path}${separator}bundle${separator}bin${separator}qwen3-asr.exe',
      );
      await runtime.parent.create(recursive: true);
      await runtime.writeAsString('runtime');

      final result = await service.moveToParent(existingRoot.path);

      expect(result.adoptedExisting, isTrue);
      expect(result.targetRoot, existingRoot.absolute.path);
      expect((await service.resolveRoot()).path, existingRoot.absolute.path);
      expect(
        await Directory(
          '${existingRoot.path}${separator}LyricForge${separator}ASRRuntime',
        ).exists(),
        isFalse,
      );
      expect(await runtime.readAsString(), 'runtime');
    },
  );

  test('resolveRoot unwraps a repeated nested root to the stronger outer root', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'lyricforge-asr-unwrap-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final separator = Platform.pathSeparator;
    final support = Directory('${sandbox.path}${separator}support');
    await support.create(recursive: true);

    final outerRoot = Directory(
      '${sandbox.path}${separator}Models${separator}LyricForge${separator}ASRRuntime',
    );
    final nestedRoot = Directory(
      '${outerRoot.path}${separator}LyricForge${separator}ASRRuntime',
    );
    final whisper = File(
      '${outerRoot.path}${separator}models${separator}whisper${separator}ggml-large-v3.bin',
    );
    await whisper.parent.create(recursive: true);
    await whisper.writeAsString('existing-whisper');
    final runtime = File(
      '${outerRoot.path}${separator}bundle${separator}bin${separator}qwen3-asr.exe',
    );
    await runtime.parent.create(recursive: true);
    await runtime.writeAsString('runtime');
    await File(
      '${outerRoot.path}${separator}.runtime-health-v1.json',
    ).writeAsString('{}');

    final nestedPartial = File(
      '${nestedRoot.path}${separator}downloads${separator}asr-runtime.zip.part',
    );
    await nestedPartial.parent.create(recursive: true);
    await nestedPartial.writeAsString('partial');

    final configFile = File(
      '${support.path}${separator}LyricForge${separator}asr-managed-storage.json',
    );
    await configFile.parent.create(recursive: true);
    await configFile.writeAsString(
      jsonEncode({'schemaVersion': 2, 'managedRoot': nestedRoot.absolute.path}),
    );

    final service = LocalAsrManagedStorageService(
      supportDirectoryResolver: () async => support,
    );

    expect((await service.resolveRoot()).path, outerRoot.absolute.path);
    expect(await nestedPartial.readAsString(), 'partial');
    final config =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    expect(config['managedRoot'], outerRoot.absolute.path);
  });

  test(
    'adopts an outer existing root even when the active root is nested inside it',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'lyricforge-asr-ancestor-adopt-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final separator = Platform.pathSeparator;
      final support = Directory('${sandbox.path}${separator}support');
      await support.create(recursive: true);

      final outerRoot = Directory(
        '${sandbox.path}${separator}Models${separator}LyricForge${separator}ASRRuntime',
      );
      final nestedRoot = Directory(
        '${outerRoot.path}${separator}LyricForge${separator}ASRRuntime',
      );
      await outerRoot.create(recursive: true);
      await File(
        '${outerRoot.path}${separator}.runtime-health-v1.json',
      ).writeAsString('{}');
      final nestedWhisper = File(
        '${nestedRoot.path}${separator}models${separator}whisper${separator}ggml-large-v3.bin',
      );
      await nestedWhisper.parent.create(recursive: true);
      await nestedWhisper.writeAsString('nested-partial-environment');
      final nestedRuntime = File(
        '${nestedRoot.path}${separator}bundle${separator}bin${separator}qwen3-asr.exe',
      );
      await nestedRuntime.parent.create(recursive: true);
      await nestedRuntime.writeAsString('nested-runtime');

      final configFile = File(
        '${support.path}${separator}LyricForge${separator}asr-managed-storage.json',
      );
      await configFile.parent.create(recursive: true);
      await configFile.writeAsString(
        jsonEncode({
          'schemaVersion': 2,
          'managedRoot': nestedRoot.absolute.path,
        }),
      );

      final service = LocalAsrManagedStorageService(
        supportDirectoryResolver: () async => support,
      );
      final result = await service.moveToParent(outerRoot.path);

      expect(result.adoptedExisting, isTrue);
      expect(result.moved, isTrue);
      expect(result.targetRoot, outerRoot.absolute.path);
      expect((await service.resolveRoot()).path, outerRoot.absolute.path);
      expect(await nestedWhisper.readAsString(), 'nested-partial-environment');
    },
  );

  test(
    'discoverAndAdoptExisting finds a Models/LyricForge root with bounded search',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'lyricforge-asr-discover-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final separator = Platform.pathSeparator;
      final support = Directory('${sandbox.path}${separator}support');
      await support.create(recursive: true);
      final service = LocalAsrManagedStorageService(
        supportDirectoryResolver: () async => support,
      );
      final source = await service.resolveRoot();
      await File('${source.path}${separator}keep.bin').writeAsString('keep');

      final existingRoot = Directory(
        '${sandbox.path}${separator}Models${separator}LyricForge${separator}ASRRuntime',
      );
      final whisper = File(
        '${existingRoot.path}${separator}models${separator}whisper${separator}ggml-large-v3.bin',
      );
      await whisper.parent.create(recursive: true);
      await whisper.writeAsString('existing');
      await File(
        '${existingRoot.path}${separator}.runtime-health-v1.json',
      ).writeAsString('{}');

      final result = await service.discoverAndAdoptExisting();

      expect(result, isNotNull);
      expect(result!.adoptedExisting, isTrue);
      expect(result.targetRoot, existingRoot.absolute.path);
      expect((await service.resolveRoot()).path, existingRoot.absolute.path);
      expect(
        await File('${source.path}${separator}keep.bin').readAsString(),
        'keep',
      );
    },
  );

  test(
    'adoptExistingAt finds Models/LyricForge below a drive-like selection',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'lyricforge-asr-drive-selection-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final separator = Platform.pathSeparator;
      final support = Directory('${sandbox.path}${separator}support');
      final drive = Directory('${sandbox.path}${separator}drive-d');
      await support.create(recursive: true);
      await drive.create(recursive: true);
      final service = LocalAsrManagedStorageService(
        supportDirectoryResolver: () async => support,
      );
      await service.resolveRoot();

      final existingRoot = Directory(
        '${drive.path}${separator}Models${separator}LyricForge${separator}ASRRuntime',
      );
      final qwenMarker = File(
        '${existingRoot.path}${separator}models${separator}qwen${separator}Qwen--Qwen3-ASR-1.7B${separator}.lyricforge-model.json',
      );
      await qwenMarker.parent.create(recursive: true);
      await qwenMarker.writeAsString('{}');

      final result = await service.adoptExistingAt(drive.path);

      expect(result.adoptedExisting, isTrue);
      expect(result.targetRoot, existingRoot.absolute.path);
      expect((await service.resolveRoot()).path, existingRoot.absolute.path);
    },
  );

  test(
    'adoptExistingAt accepts a quoted model file path inside the root',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'lyricforge-asr-pasted-file-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final separator = Platform.pathSeparator;
      final support = Directory('${sandbox.path}${separator}support');
      await support.create(recursive: true);
      final service = LocalAsrManagedStorageService(
        supportDirectoryResolver: () async => support,
      );
      await service.resolveRoot();

      final existingRoot = Directory(
        '${sandbox.path}${separator}existing${separator}ASRRuntime',
      );
      final whisper = File(
        '${existingRoot.path}${separator}models${separator}whisper${separator}ggml-large-v3.bin',
      );
      await whisper.parent.create(recursive: true);
      await whisper.writeAsString('existing');

      final result = await service.adoptExistingAt('"${whisper.path}"');

      expect(result.adoptedExisting, isTrue);
      expect(result.targetRoot, existingRoot.absolute.path);
    },
  );

  test(
    'adoptExistingAt does not migrate into an unrelated non-empty folder',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'lyricforge-asr-adopt-foreign-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final separator = Platform.pathSeparator;
      final support = Directory('${sandbox.path}${separator}support');
      final foreign = Directory('${sandbox.path}${separator}foreign');
      await support.create(recursive: true);
      await foreign.create(recursive: true);
      await File('${foreign.path}${separator}notes.txt').writeAsString('mine');
      final service = LocalAsrManagedStorageService(
        supportDirectoryResolver: () async => support,
      );
      final source = await service.resolveRoot();
      await File('${source.path}${separator}keep.bin').writeAsString('keep');

      await expectLater(
        service.adoptExistingAt(foreign.path),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.message,
            'message',
            contains('未在该路径'),
          ),
        ),
      );

      expect((await service.resolveRoot()).path, source.path);
      expect(
        await Directory(
          '${foreign.path}${separator}LyricForge${separator}ASRRuntime',
        ).exists(),
        isFalse,
      );
      expect(
        await File('${foreign.path}${separator}notes.txt').readAsString(),
        'mine',
      );
    },
  );

  test(
    'refuses a migration target nested inside the current ASR root',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'lyricforge-asr-overlap-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final support = Directory(
        '${sandbox.path}${Platform.pathSeparator}support',
      );
      await support.create(recursive: true);
      final service = LocalAsrManagedStorageService(
        supportDirectoryResolver: () async => support,
      );
      final source = await service.resolveRoot();
      final sourceFile = File(
        '${source.path}${Platform.pathSeparator}keep.bin',
      );
      await sourceFile.writeAsString('keep-me');

      final nestedParent = Directory(
        '${source.path}${Platform.pathSeparator}nested-destination',
      );
      await expectLater(
        service.moveToParent(nestedParent.path),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.message,
            'message',
            contains('不能位于当前 ASRRuntime 目录内部'),
          ),
        ),
      );

      expect((await service.resolveRoot()).path, source.path);
      expect(await sourceFile.readAsString(), 'keep-me');
      expect(service.isMoving, isFalse);
    },
  );

  test('persists and restores a macOS security-scoped storage bookmark', () async {
    final sandbox = await Directory.systemTemp.createTemp(
      'lyricforge-asr-bookmark-',
    );
    addTearDown(() => sandbox.delete(recursive: true));
    final support = Directory(
      '${sandbox.path}${Platform.pathSeparator}support',
    );
    final destination = Directory(
      '${sandbox.path}${Platform.pathSeparator}external',
    );
    await support.create(recursive: true);
    await destination.create(recursive: true);

    final bridge = _FakeBookmarkBridge(createdBookmark: 'bookmark-v2');
    final service = LocalAsrManagedStorageService(
      supportDirectoryResolver: () async => support,
      securityScopedBookmarkBridge: bridge,
      isMacOSResolver: () => true,
    );
    final source = await service.resolveRoot();
    await File(
      '${source.path}${Platform.pathSeparator}keep.bin',
    ).writeAsString('keep');

    await service.moveToParent(destination.path);
    final expected = Directory(
      '${destination.path}${Platform.pathSeparator}LyricForge${Platform.pathSeparator}ASRRuntime',
    ).absolute.path;

    final configFile = File(
      '${support.path}${Platform.pathSeparator}LyricForge${Platform.pathSeparator}asr-managed-storage.json',
    );
    final config =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    expect(config['schemaVersion'], 2);
    expect(config['securityScopedBookmark'], 'bookmark-v2');
    expect(config['securityScopedParent'], destination.absolute.path);

    final restoreBridge = _FakeBookmarkBridge(
      createdBookmark: 'unused',
      restoredPath: destination.absolute.path,
      restoredBookmark: 'bookmark-v2',
    );
    final restoredService = LocalAsrManagedStorageService(
      supportDirectoryResolver: () async => support,
      securityScopedBookmarkBridge: restoreBridge,
      isMacOSResolver: () => true,
    );
    expect((await restoredService.resolveRoot()).path, expected);
    expect(restoreBridge.restoredBookmarks, ['bookmark-v2']);
    expect(
      await File('$expected${Platform.pathSeparator}keep.bin').readAsString(),
      'keep',
    );
  });

  test(
    'reauthorizes a legacy macOS root in place without losing part files',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'lyricforge-asr-legacy-',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final support = Directory(
        '${sandbox.path}${Platform.pathSeparator}support',
      );
      final selectedParent = Directory(
        '${sandbox.path}${Platform.pathSeparator}external',
      );
      final legacyRoot = Directory(
        '${selectedParent.path}${Platform.pathSeparator}LyricForge${Platform.pathSeparator}ASRRuntime',
      );
      await support.create(recursive: true);
      await legacyRoot.create(recursive: true);
      final part = File(
        '${legacyRoot.path}${Platform.pathSeparator}downloads${Platform.pathSeparator}asr-runtime.zip.part',
      );
      await part.parent.create(recursive: true);
      await part.writeAsBytes(List<int>.filled(333, 9));

      final configFile = File(
        '${support.path}${Platform.pathSeparator}LyricForge${Platform.pathSeparator}asr-managed-storage.json',
      );
      await configFile.parent.create(recursive: true);
      await configFile.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'managedRoot': legacyRoot.absolute.path,
        }),
      );

      final bridge = _FakeBookmarkBridge(createdBookmark: 'legacy-upgraded');
      final service = LocalAsrManagedStorageService(
        supportDirectoryResolver: () async => support,
        securityScopedBookmarkBridge: bridge,
        isMacOSResolver: () => true,
      );

      expect(await service.needsSecurityScopedAuthorization(), isTrue);
      final result = await service.moveToParent(selectedParent.path);
      expect(result.moved, isFalse);
      expect(await part.length(), 333);
      expect(await service.needsSecurityScopedAuthorization(), isFalse);

      final config =
          jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
      expect(config['schemaVersion'], 2);
      expect(config['securityScopedBookmark'], 'legacy-upgraded');
      expect(bridge.createdPaths, [selectedParent.absolute.path]);
    },
  );
}

class _FakeBookmarkBridge implements AsrSecurityScopedBookmarkBridge {
  final String createdBookmark;
  final String? restoredPath;
  final String? restoredBookmark;
  final List<String> createdPaths = [];
  final List<String> restoredBookmarks = [];

  _FakeBookmarkBridge({
    required this.createdBookmark,
    this.restoredPath,
    this.restoredBookmark,
  });

  @override
  Future<AsrSecurityScopedBookmarkAccess> createAndStart(String path) async {
    final absolute = Directory(path).absolute.path;
    createdPaths.add(absolute);
    return AsrSecurityScopedBookmarkAccess(
      path: absolute,
      bookmark: createdBookmark,
    );
  }

  @override
  Future<AsrSecurityScopedBookmarkAccess> restoreAndStart(
    String bookmark,
  ) async {
    restoredBookmarks.add(bookmark);
    final path = restoredPath;
    if (path == null) {
      throw StateError('No restored path configured');
    }
    return AsrSecurityScopedBookmarkAccess(
      path: path,
      bookmark: restoredBookmark ?? bookmark,
    );
  }
}
