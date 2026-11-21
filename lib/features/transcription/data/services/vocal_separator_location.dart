import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where the vocal separator is installed: a `VocalSeparator` folder inside
/// the shared model folder, beside the recognition runtime and its models
/// (D-049).
///
/// Earlier builds put the separator in the application support folder, so
/// the program kept its models in two places and a user who moved the
/// recognition environment to another disk still had about 700 MB on the
/// system disk. Now the separator lives in the folder the settings show and
/// moves with it, because a storage move copies the whole folder.
///
/// A separator installed by an earlier build is moved over the first time it
/// is needed: renamed when both folders are on one disk, copied otherwise.
/// When neither works, for example because the old program files are still
/// open, the old copy keeps being used, so nothing is downloaded again; the
/// move is tried again on the next start.
class VocalSeparatorLocation {
  VocalSeparatorLocation({
    required Future<Directory> Function() modelRoot,
    Future<Directory> Function()? legacyRoot,
  }) : _modelRoot = modelRoot,
       _legacyRoot = legacyRoot ?? defaultLegacyRoot;

  /// The folder's name inside the shared model folder.
  static const String folderName = 'VocalSeparator';

  /// The name of the installed bundle inside the separator's folder.
  static const String installedBundle = 'current';

  /// A copy in progress; renamed to [installedBundle] once complete.
  static const String movingBundle = 'moving';

  final Future<Directory> Function() _modelRoot;
  final Future<Directory> Function() _legacyRoot;

  /// One move at a time; a caller that arrives meanwhile waits for it.
  Future<Directory>? _pending;

  /// Where earlier builds installed the separator.
  static Future<Directory> defaultLegacyRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(_join(support.path, ['LyricForge', folderName]));
  }

  /// The separator's folder inside [modelRoot].
  static Directory inside(Directory modelRoot) =>
      Directory(_join(modelRoot.path, [folderName]));

  /// The folder to install into and run from.
  Future<Directory> resolve() {
    final pending = _pending;
    if (pending != null) return pending;
    final next = _resolve();
    _pending = next;
    return next.whenComplete(() => _pending = null);
  }

  Future<Directory> _resolve() async {
    final target = inside(await _modelRoot());
    final legacy = await _legacyRoot();
    if (_samePath(target.path, legacy.path) || !await legacy.exists()) {
      return target;
    }
    final legacyBundle = Directory(_join(legacy.path, [installedBundle]));
    final targetBundle = Directory(_join(target.path, [installedBundle]));
    if (!await legacyBundle.exists()) {
      // Only an unfinished download or an empty layout is left there.
      await _deleteQuietly(legacy);
      return target;
    }
    if (await targetBundle.exists()) {
      // Moved before, but the old copy could not be deleted then.
      await _deleteQuietly(legacy);
      return target;
    }
    if (await _move(legacyBundle, targetBundle)) {
      await _deleteQuietly(legacy);
      return target;
    }
    return legacy;
  }

  /// Moves an installed bundle; false leaves [from] as it was.
  Future<bool> _move(Directory from, Directory to) async {
    try {
      await to.parent.create(recursive: true);
      await from.rename(to.path);
      return true;
    } on FileSystemException {
      // Another disk, or a file is open: copy instead.
    }
    final moving = Directory(_join(to.parent.path, [movingBundle]));
    try {
      await _deleteQuietly(moving);
      await _copyTree(from, moving);
      await moving.rename(to.path);
      return true;
    } on FileSystemException {
      await _deleteQuietly(moving);
      return false;
    }
  }

  static Future<void> _copyTree(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final entity in from.list(followLinks: false)) {
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      final destination = _join(to.path, [name]);
      if (entity is Directory) {
        await _copyTree(entity, Directory(destination));
      } else if (entity is File) {
        await entity.copy(destination);
      }
    }
  }

  static Future<void> _deleteQuietly(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // A locked file stays until the next start tries again.
    }
  }

  static bool _samePath(String a, String b) {
    String normal(String value) {
      var path = value.replaceAll('\\', '/');
      while (path.length > 1 && path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }
      return Platform.isWindows ? path.toLowerCase() : path;
    }

    return normal(a) == normal(b);
  }

  static String _join(String root, List<String> parts) =>
      [root, ...parts].join(Platform.pathSeparator);
}
