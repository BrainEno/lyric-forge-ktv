import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/vocal_separator_location.dart';

// D-049: the vocal separator lives in the shared model folder, and a copy
// installed by an earlier build is moved there instead of downloaded again.

String _join(List<String> parts) => parts.join(Platform.pathSeparator);

class _Folders {
  _Folders(this.base);

  final Directory base;

  Directory get models => Directory(_join([base.path, 'ASRRuntime']));
  Directory get legacy =>
      Directory(_join([base.path, 'support', 'LyricForge', 'VocalSeparator']));
  Directory get target =>
      Directory(_join([models.path, VocalSeparatorLocation.folderName]));

  VocalSeparatorLocation location({Future<Directory> Function()? modelRoot}) =>
      VocalSeparatorLocation(
        modelRoot: modelRoot ?? () async => models,
        legacyRoot: () async => legacy,
      );

  /// An installed bundle as the separator runtime lays it out.
  Future<void> install(Directory root) async {
    final current = _join([root.path, 'current']);
    await Directory(_join([current, 'bin'])).create(recursive: true);
    await Directory(_join([current, 'models'])).create(recursive: true);
    await File(
      _join([current, 'bin', 'lyricforge-separator.exe']),
    ).writeAsString('exe');
    await File(
      _join([current, 'models', 'htdemucs_ft_vocals.onnx']),
    ).writeAsBytes(List<int>.generate(2048, (i) => i % 251));
    await File(
      _join([current, 'separator-manifest.json']),
    ).writeAsString('{}');
  }

  File model(Directory root) => File(
    _join([root.path, 'current', 'models', 'htdemucs_ft_vocals.onnx']),
  );
}

Future<_Folders> _folders() async {
  final base = await Directory.systemTemp.createTemp('separator-location-');
  addTearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });
  return _Folders(base);
}

void main() {
  test('the folder sits inside the shared model folder', () async {
    final folders = await _folders();
    final resolved = await folders.location().resolve();
    expect(resolved.path, folders.target.path);
    expect(
      VocalSeparatorLocation.inside(folders.models).path,
      folders.target.path,
    );
  });

  test('a fresh install has nothing to move', () async {
    final folders = await _folders();
    await folders.location().resolve();
    expect(await folders.legacy.exists(), isFalse);
    // The runtime creates the folder itself when it installs.
    expect(await folders.target.exists(), isFalse);
  });

  test('an installed separator is moved over, not downloaded again', () async {
    final folders = await _folders();
    await folders.install(folders.legacy);
    final before = await folders.model(folders.legacy).readAsBytes();

    final resolved = await folders.location().resolve();

    expect(resolved.path, folders.target.path);
    expect(await folders.model(folders.target).readAsBytes(), before);
    expect(
      await File(
        _join([
          folders.target.path,
          'current',
          'bin',
          'lyricforge-separator.exe',
        ]),
      ).readAsString(),
      'exe',
    );
    expect(await folders.legacy.exists(), isFalse);
  });

  test('the move happens once; later calls find it in place', () async {
    final folders = await _folders();
    await folders.install(folders.legacy);
    final location = folders.location();
    await location.resolve();
    final again = await location.resolve();
    expect(again.path, folders.target.path);
    expect(await folders.model(folders.target).exists(), isTrue);
  });

  test('concurrent callers share one move', () async {
    final folders = await _folders();
    await folders.install(folders.legacy);
    final location = folders.location();
    final results = await Future.wait([
      location.resolve(),
      location.resolve(),
      location.resolve(),
    ]);
    for (final result in results) {
      expect(result.path, folders.target.path);
    }
    expect(await folders.model(folders.target).exists(), isTrue);
    expect(await folders.legacy.exists(), isFalse);
  });

  test('an old copy left beside a moved one is removed', () async {
    final folders = await _folders();
    await folders.install(folders.target);
    await folders.install(folders.legacy);
    await File(
      _join([folders.target.path, 'current', 'marker']),
    ).writeAsString('kept');

    final resolved = await folders.location().resolve();

    expect(resolved.path, folders.target.path);
    expect(
      await File(
        _join([folders.target.path, 'current', 'marker']),
      ).readAsString(),
      'kept',
    );
    expect(await folders.legacy.exists(), isFalse);
  });

  test('an unfinished old download is only cleaned up', () async {
    final folders = await _folders();
    final downloads = Directory(_join([folders.legacy.path, 'downloads']));
    await downloads.create(recursive: true);
    await File(_join([downloads.path, 'sep.zip.part'])).writeAsString('half');

    final resolved = await folders.location().resolve();

    expect(resolved.path, folders.target.path);
    expect(await folders.legacy.exists(), isFalse);
    expect(await Directory(_join([folders.target.path, 'current'])).exists(),
        isFalse);
  });

  test('a target folder with only downloads still receives the bundle', () async {
    final folders = await _folders();
    await Directory(
      _join([folders.target.path, 'downloads']),
    ).create(recursive: true);
    await folders.install(folders.legacy);

    final resolved = await folders.location().resolve();

    expect(resolved.path, folders.target.path);
    expect(await folders.model(folders.target).exists(), isTrue);
    expect(
      await Directory(_join([folders.target.path, 'downloads'])).exists(),
      isTrue,
    );
  });

  test('when the old place is the new place nothing moves', () async {
    final folders = await _folders();
    await folders.install(folders.target);
    final location = VocalSeparatorLocation(
      modelRoot: () async => folders.models,
      legacyRoot: () async => folders.target,
    );
    final resolved = await location.resolve();
    expect(resolved.path, folders.target.path);
    expect(await folders.model(folders.target).exists(), isTrue);
  });

  test('a move that cannot be done keeps using the old copy', () async {
    final folders = await _folders();
    await folders.install(folders.legacy);
    // A file where the model folder should be: neither a rename nor a copy
    // can create the separator's folder below it.
    await folders.base.create(recursive: true);
    final blocker = File(_join([folders.base.path, 'blocked']));
    await blocker.writeAsString('not a folder');
    final location = VocalSeparatorLocation(
      modelRoot: () async => Directory(blocker.path),
      legacyRoot: () async => folders.legacy,
    );

    final resolved = await location.resolve();

    expect(resolved.path, folders.legacy.path);
    expect(await folders.model(folders.legacy).exists(), isTrue);
  });

  test('the model folder follows the configured location each time', () async {
    final folders = await _folders();
    var root = folders.models;
    final location = VocalSeparatorLocation(
      modelRoot: () async => root,
      legacyRoot: () async => folders.legacy,
    );
    expect((await location.resolve()).path, folders.target.path);
    root = Directory(_join([folders.base.path, 'D', 'ASRRuntime']));
    expect(
      (await location.resolve()).path,
      _join([root.path, VocalSeparatorLocation.folderName]),
    );
  });
}
