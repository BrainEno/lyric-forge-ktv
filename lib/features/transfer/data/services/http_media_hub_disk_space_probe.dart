import 'dart:io';

/// PowerShell script used by [probeAvailableDiskSpaceBytes] on Windows.
///
/// The upload directory is passed through the `LYRICFORGE_UPLOAD_PATH`
/// environment variable so the path never needs shell quoting. The script
/// prints the available free bytes of the drive that holds the directory and
/// exits with code 3 when the path root is not a drive-letter root.
///
/// Kept as a named constant (instead of an inline literal) so
/// `media_hub_disk_space_probe_contract_test.dart` can pin its exact content
/// and execute it under real PowerShell on Windows CI. A corrupted copy of
/// this script once shipped inside the string literal and silently broke
/// every Windows incoming upload with 507 responses (issue #255).
const String mediaHubWindowsDiskSpaceProbeScript = r'''
$path = $env:LYRICFORGE_UPLOAD_PATH
$root = [System.IO.Path]::GetPathRoot($path)
if ($root -notmatch '^[A-Za-z]:\\$') { exit 3 }
$drive = New-Object System.IO.DriveInfo -ArgumentList $root
[Console]::Out.Write([string]$drive.AvailableFreeSpace)''';

/// Probes the available free bytes on the filesystem containing [directory].
Future<int?> probeAvailableDiskSpaceBytes(Directory directory) async {
  try {
    if (Platform.isWindows) {
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          mediaHubWindowsDiskSpaceProbeScript,
        ],
        environment: {'LYRICFORGE_UPLOAD_PATH': directory.absolute.path},
      );
      if (result.exitCode != 0) return null;
      final freeBytes = int.tryParse(result.stdout.toString().trim());
      return freeBytes != null && freeBytes >= 0 ? freeBytes : null;
    }

    if (!Platform.isLinux && !Platform.isMacOS) return null;

    final result = await Process.run('df', ['-Pk', directory.absolute.path]);
    if (result.exitCode != 0) return null;
    final lines = result.stdout
        .toString()
        .trim()
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) return null;
    final columns = lines.last.trim().split(RegExp(r'\s+'));
    if (columns.length < 4) return null;
    final availableBlocks = int.tryParse(columns[3]);
    if (availableBlocks == null ||
        availableBlocks < 0 ||
        availableBlocks > 0x7fffffffffffffff ~/ 1024) {
      return null;
    }
    return availableBlocks * 1024;
  } catch (_) {
    return null;
  }
}
