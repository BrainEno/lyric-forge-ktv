import 'package:flutter/material.dart';

import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../domain/services/lyric_export_encoder.dart';
import '../../domain/services/lyric_file_export_service.dart';
import '../widgets/lyric_export_dialog.dart';

/// Runs the export flow: format dialog, save dialog, result message.
///
/// Kept out of the editor screen so the screen stays a thin host. The last
/// chosen format and options are remembered for the editor's lifetime, so
/// exporting the same song again after another correction is two clicks.
class LyricExportCoordinator {
  LyricExportCoordinator();

  LyricExportFormat _format = LyricExportFormat.lrc;
  LyricExportOptions _options = const LyricExportOptions(lrcEndMarkers: true);

  LyricExportFormat get lastFormat => _format;
  LyricExportOptions get lastOptions => _options;

  Future<void> export(
    BuildContext context, {
    required LyricFileExportService service,
    required ProjectManifest project,
    required LyricDocument? document,
  }) async {
    if (document == null || document.lines.isEmpty) return;
    final metadata = LyricExportMetadata(
      title: project.name,
      artist: project.artist,
      album: project.album,
    );
    final request = await showLyricExportDialog(
      context,
      document: document,
      initialFormat: _format,
      initialOptions: _options,
      audioDuration: project.audioAsset?.duration,
      metadata: metadata,
    );
    if (request == null || !context.mounted) return;
    _format = request.format;
    _options = request.options;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await service.exportFile(
        document,
        format: request.format,
        suggestedFileName: project.name,
        options: request.options,
        metadata: metadata,
      );
      if (path == null) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${request.format.label}已导出：$path')),
      );
    } on LyricExportException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('导出歌词失败：$error')));
    }
  }
}
