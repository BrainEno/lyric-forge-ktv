import 'dart:convert';
import 'dart:io';

enum AtomicJsonRecoveryResult {
  primaryValid,
  restoredFromTemporary,
  restoredFromBackup,
  noValidDocument,
}

enum AtomicJsonWriteStage {
  temporaryFlushed,
  backupPrepared,
  canonicalRemoved,
  canonicalReplaced,
}

typedef AtomicJsonValidator = bool Function(Object? decoded);
typedef AtomicJsonWriteHook = Future<void> Function(AtomicJsonWriteStage stage);

/// Writes JSON documents while keeping the previous valid version recoverable.
///
/// Sidecars live beside the destination, keeping replacement on the same
/// filesystem. If a process stops after removing the canonical file, startup
/// can restore the flushed temporary document or the last valid backup.
abstract final class AtomicJsonFile {
  static File temporaryFor(File destination) => File('${destination.path}.tmp');

  static File backupFor(File destination) => File('${destination.path}.bak');

  static File backupTemporaryFor(File destination) =>
      File('${destination.path}.bak.tmp');

  static File recoveryTemporaryFor(File destination) =>
      File('${destination.path}.recovery.tmp');

  static Future<bool> isValidJsonFile(
    File file, {
    required AtomicJsonValidator validate,
  }) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      return validate(decoded);
    } catch (_) {
      return false;
    }
  }

  /// Restores a valid sidecar only when the canonical document is missing or
  /// invalid. A valid canonical document always wins over stale sidecars.
  static Future<AtomicJsonRecoveryResult> recoverIfNeeded(
    File destination, {
    required AtomicJsonValidator validate,
  }) async {
    if (await isValidJsonFile(destination, validate: validate)) {
      return AtomicJsonRecoveryResult.primaryValid;
    }

    final candidates = <({File file, AtomicJsonRecoveryResult result})>[
      (
        file: temporaryFor(destination),
        result: AtomicJsonRecoveryResult.restoredFromTemporary,
      ),
      (
        file: backupFor(destination),
        result: AtomicJsonRecoveryResult.restoredFromBackup,
      ),
      (
        file: backupTemporaryFor(destination),
        result: AtomicJsonRecoveryResult.restoredFromBackup,
      ),
    ];

    for (final candidate in candidates) {
      if (!await isValidJsonFile(candidate.file, validate: validate)) continue;
      await _restoreCandidate(candidate.file, destination, validate: validate);
      if (candidate.file.path == temporaryFor(destination).path ||
          candidate.file.path == backupTemporaryFor(destination).path) {
        try {
          if (await candidate.file.exists()) await candidate.file.delete();
        } catch (_) {
          // A stale sidecar is harmless after the canonical document is valid.
        }
      }
      return candidate.result;
    }

    return AtomicJsonRecoveryResult.noValidDocument;
  }

  static Future<void> write(
    File destination,
    String contents, {
    required AtomicJsonValidator validate,
    AtomicJsonWriteHook? onStage,
  }) async {
    await recoverIfNeeded(destination, validate: validate);

    final decodedPayload = jsonDecode(contents);
    if (!validate(decodedPayload)) {
      throw const FormatException(
        'Refusing to write a JSON document that does not match its store schema.',
      );
    }
    if (await destination.exists() &&
        !await isValidJsonFile(destination, validate: validate)) {
      throw FileSystemException(
        'Refusing to overwrite an invalid JSON store without a recoverable copy.',
        destination.path,
      );
    }

    await destination.parent.create(recursive: true);
    final temporary = temporaryFor(destination);
    final backup = backupFor(destination);
    final backupTemporary = backupTemporaryFor(destination);

    try {
      await temporary.writeAsString(contents, flush: true);
      if (!await isValidJsonFile(temporary, validate: validate)) {
        throw FileSystemException(
          'The temporary JSON document failed validation.',
          temporary.path,
        );
      }
      await onStage?.call(AtomicJsonWriteStage.temporaryFlushed);

      if (await destination.exists()) {
        await backupTemporary.writeAsBytes(
          await destination.readAsBytes(),
          flush: true,
        );
        if (!await isValidJsonFile(backupTemporary, validate: validate)) {
          throw FileSystemException(
            'The previous JSON document could not be backed up safely.',
            destination.path,
          );
        }
        if (await backup.exists()) await backup.delete();
        await backupTemporary.rename(backup.path);
        await onStage?.call(AtomicJsonWriteStage.backupPrepared);

        // A verified backup exists before the canonical file is removed.
        await destination.delete();
        await onStage?.call(AtomicJsonWriteStage.canonicalRemoved);
      }

      await temporary.rename(destination.path);
      await onStage?.call(AtomicJsonWriteStage.canonicalReplaced);
    } catch (error, stackTrace) {
      try {
        if (!await isValidJsonFile(destination, validate: validate) &&
            await isValidJsonFile(backup, validate: validate)) {
          await _restoreCandidate(backup, destination, validate: validate);
        }
      } catch (_) {
        // Preserve the original error; the backup remains for startup recovery.
      }
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {
        // Startup recovery also checks the temporary sidecar.
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      try {
        if (await backupTemporary.exists()) await backupTemporary.delete();
      } catch (_) {}
    }
  }

  static Future<void> _restoreCandidate(
    File source,
    File destination, {
    required AtomicJsonValidator validate,
  }) async {
    final recoveryTemporary = recoveryTemporaryFor(destination);
    await recoveryTemporary.writeAsBytes(
      await source.readAsBytes(),
      flush: true,
    );
    if (!await isValidJsonFile(recoveryTemporary, validate: validate)) {
      throw FileSystemException(
        'A recovery candidate failed validation.',
        source.path,
      );
    }

    if (await destination.exists()) await destination.delete();
    await recoveryTemporary.rename(destination.path);
  }
}
