import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One entry of a zip central directory.
class ZipEntryInfo {
  const ZipEntryInfo({required this.path, required this.uncompressedSize});

  /// Normalised relative path with `/` separators.
  final String path;
  final int uncompressedSize;

  bool get isDirectory => path.endsWith('/');

  /// The last path segment.
  String get name {
    final trimmed = isDirectory ? path.substring(0, path.length - 1) : path;
    final slash = trimmed.lastIndexOf('/');
    return slash < 0 ? trimmed : trimmed.substring(slash + 1);
  }
}

/// Reads the file list of a zip archive without extracting it.
///
/// Only the end-of-central-directory record (classic or ZIP64) and the
/// central directory are read, so listing a 1.2 GB runtime bundle costs a
/// few kilobytes of I/O.
class ZipCentralDirectory {
  ZipCentralDirectory._();

  static const int _eocdSignature = 0x06054b50;
  static const int _zip64LocatorSignature = 0x07064b50;
  static const int _zip64EocdSignature = 0x06064b50;
  static const int _entrySignature = 0x02014b50;
  static const int _eocdSize = 22;
  static const int _maxCommentLength = 0xffff;
  static const int _maxDirectoryBytes = 64 * 1024 * 1024;

  /// Lists the entries of [archive].
  ///
  /// Throws [FormatException] when the file is not a readable zip archive
  /// or names an entry outside the extraction directory.
  static Future<List<ZipEntryInfo>> read(File archive) async {
    final file = await archive.open();
    try {
      final length = await file.length();
      if (length < _eocdSize) {
        throw const FormatException('file is too small to be a zip archive');
      }
      final tailLength = length < _eocdSize + _maxCommentLength + 20
          ? length
          : _eocdSize + _maxCommentLength + 20;
      final tailStart = length - tailLength;
      final tail = await _readAt(file, tailStart, tailLength);
      final view = ByteData.sublistView(tail);

      var eocd = -1;
      for (var i = tail.length - _eocdSize; i >= 0; i--) {
        if (view.getUint32(i, Endian.little) == _eocdSignature) {
          eocd = i;
          break;
        }
      }
      if (eocd < 0) {
        throw const FormatException('end of central directory not found');
      }

      var entryCount = view.getUint16(eocd + 10, Endian.little);
      var directorySize = view.getUint32(eocd + 12, Endian.little);
      var directoryOffset = view.getUint32(eocd + 16, Endian.little);

      final needsZip64 =
          entryCount == 0xffff ||
          directorySize == 0xffffffff ||
          directoryOffset == 0xffffffff;
      final locator = eocd - 20;
      if (locator >= 0 &&
          view.getUint32(locator, Endian.little) == _zip64LocatorSignature) {
        final zip64Offset = view.getUint64(locator + 8, Endian.little);
        final record = ByteData.sublistView(
          await _readAt(file, zip64Offset, 56),
        );
        if (record.getUint32(0, Endian.little) != _zip64EocdSignature) {
          throw const FormatException('ZIP64 end record is damaged');
        }
        entryCount = record.getUint64(32, Endian.little);
        directorySize = record.getUint64(40, Endian.little);
        directoryOffset = record.getUint64(48, Endian.little);
      } else if (needsZip64) {
        throw const FormatException('ZIP64 locator is missing');
      }

      if (directorySize > _maxDirectoryBytes ||
          directoryOffset + directorySize > length) {
        throw FormatException(
          'central directory is out of range '
          '(offset=$directoryOffset, size=$directorySize, file=$length)',
        );
      }
      final directory = await _readAt(file, directoryOffset, directorySize);
      return _parseEntries(directory, entryCount);
    } finally {
      await file.close();
    }
  }

  static List<ZipEntryInfo> _parseEntries(Uint8List bytes, int entryCount) {
    final view = ByteData.sublistView(bytes);
    final entries = <ZipEntryInfo>[];
    var offset = 0;
    for (var index = 0; index < entryCount; index++) {
      if (offset + 46 > bytes.length ||
          view.getUint32(offset, Endian.little) != _entrySignature) {
        throw FormatException('central directory entry $index is damaged');
      }
      final flags = view.getUint16(offset + 8, Endian.little);
      var size = view.getUint32(offset + 24, Endian.little);
      final nameLength = view.getUint16(offset + 28, Endian.little);
      final extraLength = view.getUint16(offset + 30, Endian.little);
      final commentLength = view.getUint16(offset + 32, Endian.little);
      final nameStart = offset + 46;
      final extraStart = nameStart + nameLength;
      final next = extraStart + extraLength + commentLength;
      if (next > bytes.length) {
        throw FormatException('central directory entry $index is truncated');
      }
      final rawName = bytes.sublist(nameStart, extraStart);
      // Bit 11 marks UTF-8 names; older tools write ASCII-compatible names.
      final name = (flags & 0x800) != 0
          ? utf8.decode(rawName, allowMalformed: true)
          : latin1.decode(rawName);
      if (size == 0xffffffff) {
        size = _zip64Size(view, extraStart, extraLength);
      }
      entries.add(ZipEntryInfo(path: normalisePath(name), uncompressedSize: size));
      offset = next;
    }
    return entries;
  }

  static int _zip64Size(ByteData view, int start, int length) {
    var cursor = start;
    final end = start + length;
    while (cursor + 4 <= end) {
      final id = view.getUint16(cursor, Endian.little);
      final size = view.getUint16(cursor + 2, Endian.little);
      if (id == 0x0001 && size >= 8) {
        // The uncompressed size is the first field whenever it overflowed.
        return view.getUint64(cursor + 4, Endian.little);
      }
      cursor += 4 + size;
    }
    throw const FormatException('ZIP64 size field is missing');
  }

  /// Turns an entry name into a safe relative `/` path.
  ///
  /// Throws [FormatException] for absolute names and `..` segments, which
  /// would write outside the extraction directory.
  static String normalisePath(String raw) {
    var name = raw.replaceAll('\\', '/');
    while (name.startsWith('./')) {
      name = name.substring(2);
    }
    final isDirectory = name.endsWith('/');
    final segments = name
        .split('/')
        .where((segment) => segment.isNotEmpty && segment != '.')
        .toList(growable: false);
    if (raw.startsWith('/') ||
        raw.startsWith('\\') ||
        (segments.isNotEmpty && segments.first.contains(':')) ||
        segments.contains('..')) {
      throw FormatException('unsafe zip entry path: $raw');
    }
    final joined = segments.join('/');
    return isDirectory && joined.isNotEmpty ? '$joined/' : joined;
  }

  static Future<Uint8List> _readAt(
    RandomAccessFile file,
    int offset,
    int length,
  ) async {
    await file.setPosition(offset);
    final bytes = await file.read(length);
    if (bytes.length != length) {
      throw FormatException(
        'unexpected end of file at $offset (+$length bytes)',
      );
    }
    return bytes;
  }
}

/// One extraction tool tried by [ZipBundleExtractor].
class ZipExtractionAttempt {
  const ZipExtractionAttempt({
    required this.method,
    required this.exitCode,
    required this.stderr,
    this.missing = const <String>[],
    this.extractedFiles = 0,
  });

  final String method;
  final int exitCode;
  final String stderr;

  /// Archive files absent or of the wrong size after the tool finished.
  final List<String> missing;
  final int extractedFiles;

  bool get succeeded => exitCode == 0 && missing.isEmpty && extractedFiles > 0;

  String describe() {
    final buffer = StringBuffer('[$method] exit=$exitCode, files=$extractedFiles');
    if (missing.isNotEmpty) {
      buffer.write(', missing ${missing.length}: ${missing.take(6).join(', ')}');
      if (missing.length > 6) buffer.write(', …');
    }
    final error = stderr.trim();
    if (error.isNotEmpty) {
      final short = error.length > 600 ? '${error.substring(0, 600)}…' : error;
      buffer.write('; stderr: $short');
    }
    return buffer.toString();
  }
}

/// What [ZipBundleExtractor.extract] did.
class ZipExtractionReport {
  const ZipExtractionReport({
    required this.method,
    required this.attempts,
    required this.archiveEntries,
  });

  /// The tool whose output passed the check.
  final String method;
  final List<ZipExtractionAttempt> attempts;

  /// The central directory, or null when it could not be read and the
  /// result was only checked for being non-empty.
  final List<ZipEntryInfo>? archiveEntries;

  /// Whether the archive lists a file called [fileName] anywhere; null when
  /// the directory was unreadable.
  bool? archiveContains(String fileName) {
    final entries = archiveEntries;
    if (entries == null) return null;
    final wanted = fileName.toLowerCase();
    return entries.any(
      (entry) => !entry.isDirectory && entry.name.toLowerCase() == wanted,
    );
  }
}

class ZipExtractionException implements Exception {
  const ZipExtractionException(this.message, {required this.attempts});

  final String message;
  final List<ZipExtractionAttempt> attempts;

  String get details => attempts.map((attempt) => attempt.describe()).join('\n');

  @override
  String toString() => 'ZipExtractionException($message)\n$details';
}

typedef ZipProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });

class _ExtractionTool {
  const _ExtractionTool(
    this.method,
    this.executable,
    this.arguments, {
    this.environment,
  });

  final String method;
  final String executable;
  final List<String> arguments;
  final Map<String, String>? environment;
}

/// Extracts a zip archive and proves the result complete.
///
/// The installer used to run a single PowerShell `Expand-Archive` and trust
/// its exit code. On some Windows machines that left the staging directory
/// without the runtime manifest even though the downloaded bundle was
/// verified, and the only trace was "missing manifest". This extractor
/// reads the archive's own file list first, then tries the available tools
/// in turn — Windows' built-in `tar.exe`, .NET `ZipFile`, then
/// `Expand-Archive` (or `unzip`, then `tar` elsewhere) — and accepts the
/// first output in which every listed file exists with its listed size.
/// Each attempt's exit code, stderr and missing files are kept for the
/// error report.
class ZipBundleExtractor {
  ZipBundleExtractor({
    ZipProcessRunner? runProcess,
    bool? isWindows,
    Map<String, String>? environment,
    bool Function(String path)? executableExists,
    Future<int?> Function(String path)? freeSpaceReader,
  }) : _freeSpaceReader = freeSpaceReader,
       _runProcess = runProcess ?? _defaultRunner,
       _isWindows = isWindows ?? Platform.isWindows,
       _environment = environment ?? Platform.environment,
       _executableExists =
           executableExists ?? ((path) => File(path).existsSync());

  final ZipProcessRunner _runProcess;
  final bool _isWindows;
  final Map<String, String> _environment;
  final bool Function(String path) _executableExists;
  final Future<int?> Function(String path)? _freeSpaceReader;

  /// Room left beyond the archive's own content, for file system overhead.
  static const int _freeSpaceMargin = 64 * 1024 * 1024;

  static Future<ProcessResult> _defaultRunner(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) {
    return Process.run(executable, arguments, environment: environment);
  }

  /// Extracts [archive] into [destination], which is emptied before each
  /// tool runs. [beforeAttempt] runs before every tool, so a cancelled
  /// install stops between attempts.
  Future<ZipExtractionReport> extract(
    File archive,
    Directory destination, {
    void Function()? beforeAttempt,
  }) async {
    List<ZipEntryInfo>? entries;
    try {
      entries = await ZipCentralDirectory.read(archive);
    } on FormatException catch (error) {
      if (error.message.startsWith('unsafe zip entry path')) {
        throw ZipExtractionException(
          '安装包包含不安全的文件路径，已拒绝解压',
          attempts: [
            ZipExtractionAttempt(
              method: 'central-directory',
              exitCode: -1,
              stderr: error.message,
            ),
          ],
        );
      }
      // Fall back to trusting the tools; they report damaged archives.
      entries = null;
    }

    await _checkFreeSpace(destination, entries);

    final attempts = <ZipExtractionAttempt>[];
    for (final tool in _tools(archive.path, destination.path)) {
      beforeAttempt?.call();
      await _reset(destination);
      ProcessResult result;
      try {
        result = await _runProcess(
          tool.executable,
          tool.arguments,
          environment: tool.environment,
        );
      } on ProcessException catch (error) {
        attempts.add(
          ZipExtractionAttempt(
            method: tool.method,
            exitCode: -1,
            stderr: error.message,
          ),
        );
        continue;
      }
      final files = await _listFiles(destination);
      final missing = result.exitCode == 0 && entries != null
          ? await _missingEntries(destination, entries)
          : const <String>[];
      final attempt = ZipExtractionAttempt(
        method: tool.method,
        exitCode: result.exitCode,
        stderr: '${result.stderr}'.trim().isEmpty
            ? '${result.stdout}'.trim()
            : '${result.stderr}',
        missing: missing,
        extractedFiles: files,
      );
      attempts.add(attempt);
      if (attempt.succeeded) {
        return ZipExtractionReport(
          method: tool.method,
          attempts: List.unmodifiable(attempts),
          archiveEntries: entries == null ? null : List.unmodifiable(entries),
        );
      }
    }
    await _reset(destination);
    throw ZipExtractionException(
      '安装包解压失败或解压结果不完整（已依次尝试 '
      '${attempts.map((attempt) => attempt.method).join('、')}）',
      attempts: List.unmodifiable(attempts),
    );
  }

  /// Refuses to start when the volume cannot hold the extracted files: an
  /// extraction that runs out of space mid-way leaves the last entries —
  /// the runtime manifest among them — missing.
  Future<void> _checkFreeSpace(
    Directory destination,
    List<ZipEntryInfo>? entries,
  ) async {
    final reader = _freeSpaceReader;
    if (reader == null || entries == null) return;
    final needed =
        entries.fold<int>(0, (sum, entry) => sum + entry.uncompressedSize) +
        _freeSpaceMargin;
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }
    int? available;
    try {
      available = await reader(destination.path);
    } catch (_) {
      available = null;
    }
    if (available == null || available >= needed) return;
    throw ZipExtractionException(
      '磁盘剩余空间不足：解压需要约 ${_formatBytes(needed)}，'
      '当前仅剩 ${_formatBytes(available)}',
      attempts: [
        ZipExtractionAttempt(
          method: 'free-space',
          exitCode: -1,
          stderr: 'needed=$needed, available=$available',
        ),
      ],
    );
  }

  static String _formatBytes(int bytes) {
    const gib = 1024 * 1024 * 1024;
    const mib = 1024 * 1024;
    if (bytes >= gib) return '${(bytes / gib).toStringAsFixed(1)} GB';
    return '${(bytes / mib).toStringAsFixed(0)} MB';
  }

  List<_ExtractionTool> _tools(String archive, String destination) {
    if (!_isWindows) {
      return [
        _ExtractionTool('unzip', '/usr/bin/unzip', [
          '-o',
          '-q',
          archive,
          '-d',
          destination,
        ]),
        _ExtractionTool('tar', 'tar', ['-xf', archive, '-C', destination]),
      ];
    }

    final systemRoot = _environment['SystemRoot'] ?? r'C:\Windows';
    final system32 = '$systemRoot\\System32';
    final tar = '$system32\\tar.exe';
    final powershellPath = '$system32\\WindowsPowerShell\\v1.0\\powershell.exe';
    final powershell = _executableExists(powershellPath)
        ? powershellPath
        : 'powershell';
    // A PowerShell 7 parent leaks its module path into Windows PowerShell,
    // which then loads modules built for the wrong runtime. Pin the 5.1 one.
    final psEnvironment = <String, String>{
      'PSModulePath': '$system32\\WindowsPowerShell\\v1.0\\Modules',
    };
    final a = _psQuote(archive);
    final d = _psQuote(destination);
    return [
      if (_executableExists(tar))
        _ExtractionTool('tar', tar, ['-x', '-f', archive, '-C', destination]),
      _ExtractionTool(
        '.NET ZipFile',
        powershell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r"$ErrorActionPreference = 'Stop'; "
              'Add-Type -AssemblyName System.IO.Compression.FileSystem; '
              '[System.IO.Compression.ZipFile]::ExtractToDirectory($a, $d)',
        ],
        environment: psEnvironment,
      ),
      _ExtractionTool(
        'Expand-Archive',
        powershell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          r"$ErrorActionPreference = 'Stop'; "
              r"$ProgressPreference = 'SilentlyContinue'; "
              'Expand-Archive -LiteralPath $a -DestinationPath $d -Force',
        ],
        environment: psEnvironment,
      ),
    ];
  }

  static String _psQuote(String value) => "'${value.replaceAll("'", "''")}'";

  static Future<void> _reset(Directory destination) async {
    if (await destination.exists()) {
      await destination.delete(recursive: true);
    }
    await destination.create(recursive: true);
  }

  static Future<int> _listFiles(Directory destination) async {
    if (!await destination.exists()) return 0;
    var count = 0;
    await for (final entity in destination.list(recursive: true)) {
      if (entity is File) count++;
    }
    return count;
  }

  static Future<List<String>> _missingEntries(
    Directory destination,
    List<ZipEntryInfo> entries,
  ) async {
    final missing = <String>[];
    for (final entry in entries) {
      if (entry.isDirectory || entry.path.isEmpty) continue;
      final file = File(
        [
          destination.path,
          ...entry.path.split('/'),
        ].join(Platform.pathSeparator),
      );
      if (!await file.exists() ||
          await file.length() != entry.uncompressedSize) {
        missing.add(entry.path);
      }
    }
    return missing;
  }

  /// Up to [limit] files under [root], relative and `/`-separated, for
  /// error reports.
  static Future<List<String>> describeTree(Directory root, {int limit = 20}) async {
    final names = <String>[];
    if (!await root.exists()) return names;
    final prefix = root.path.length + 1;
    await for (final entity in root.list(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path;
      names.add(
        (path.length > prefix ? path.substring(prefix) : path).replaceAll(
          '\\',
          '/',
        ),
      );
      if (names.length >= limit) break;
    }
    return names;
  }
}
