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
///
/// Each store declares a schema version for its document shape. Outgoing
/// payloads are stamped under [schemaVersionKey], reads validate through
/// [versioned], and a store that changes its shape bumps its version and
/// migrates older documents on load using [schemaVersionOf].
abstract final class AtomicJsonFile {
  /// Key recording a store document's schema version.
  ///
  /// Stores already wrote an ad-hoc `version` field before schema
  /// versioning was formalized, so the key adopts that name instead of
  /// introducing a second competing stamp next to it.
  static const String schemaVersionKey = 'version';

  /// Schema version assumed for documents written before versioning.
  static const int legacySchemaVersion = 0;

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

  /// Returns the schema version stamped on [decoded].
  ///
  /// Documents without a stamp predate schema versioning and report
  /// [legacySchemaVersion]. Non-object documents and malformed stamps
  /// (negative, fractional, or non-numeric) report -1 so validators can
  /// reject them as corrupt.
  static int schemaVersionOf(Object? decoded) {
    if (decoded is! Map) return -1;
    final raw = decoded[schemaVersionKey];
    if (raw == null) return legacySchemaVersion;
    if (raw is num && raw >= 0 && raw % 1 == 0) return raw.toInt();
    return -1;
  }

  /// Returns a copy of [payload] stamped with schema [version].
  ///
  /// The stamp is applied last so a stale value already present in
  /// [payload] can never win over the store's current version.
  static Map<String, dynamic> stampSchemaVersion(
    Map<String, dynamic> payload,
    int version,
  ) => {...payload, schemaVersionKey: version};

  /// Wraps [validate] with schema-version gating for a store whose current
  /// schema is [currentVersion].
  ///
  /// Legacy (unstamped) and older documents stay readable so stores can
  /// migrate them on load and restamp them on the next write. Documents
  /// stamped by a newer app version are rejected, routing them into the
  /// existing recovery / refuse-to-overwrite paths instead of letting this
  /// build silently rewrite data it does not understand.
  static AtomicJsonValidator versioned({
    required int currentVersion,
    required AtomicJsonValidator validate,
  }) {
    return (decoded) {
      final version = schemaVersionOf(decoded);
      return version >= 0 && version <= currentVersion && validate(decoded);
    };
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
        await _copyAndFlush(destination, backupTemporary);
        if (!await isValidJsonFile(backupTemporary, validate: validate)) {
          throw FileSystemException(
            'The previous JSON document could not be backed up safely.',
            destination.path,
          );
        }
        if (await backup.exists()) await backup.delete();
        await backupTemporary.rename(backup.path);
        await onStage?.call(AtomicJsonWriteStage.backupPrepared);

        // POSIX rename atomically replaces an existing destination. Windows
        // requires deleting the target first, so recovery still covers that gap.
        if (Platform.isWindows) {
          await destination.delete();
          await onStage?.call(AtomicJsonWriteStage.canonicalRemoved);
        }
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

  /// Streams a copy to avoid loading large JSON stores entirely into memory.
  static Future<void> _copyAndFlush(File source, File destination) async {
    if (await destination.exists()) await destination.delete();
    final sink = destination.openWrite();
    try {
      await for (final chunk in source.openRead()) {
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  static Future<void> _restoreCandidate(
    File source,
    File destination, {
    required AtomicJsonValidator validate,
  }) async {
    final recoveryTemporary = recoveryTemporaryFor(destination);
    await _copyAndFlush(source, recoveryTemporary);
    if (!await isValidJsonFile(recoveryTemporary, validate: validate)) {
      throw FileSystemException(
        'A recovery candidate failed validation.',
        source.path,
      );
    }

    // Use the same platform-aware replacement approach during recovery. On
    // POSIX this avoids another delete/rename gap while restoring a sidecar.
    if (Platform.isWindows && await destination.exists()) {
      await destination.delete();
    }
    await recoveryTemporary.rename(destination.path);
  }
}
