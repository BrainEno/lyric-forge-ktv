import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../player/domain/repositories/local_media_library_repository.dart';
import '../../domain/models/media_transfer_batch.dart';
import '../../domain/models/remote_audio_track.dart';
import '../../domain/services/media_hub_client_service.dart';
import '../../domain/services/media_transfer_service.dart';

class LocalMediaTransferService implements MediaTransferService {
  final MediaHubClientService client;
  final LocalMediaLibraryRepository libraryRepository;
  final Directory? downloadDirectory;

  const LocalMediaTransferService({
    required this.client,
    required this.libraryRepository,
    this.downloadDirectory,
  });

  @override
  Future<MediaTransferBatchResult> downloadRemoteTracks(
    List<RemoteAudioTrack> tracks, {
    MediaTransferProgressCallback? onProgress,
  }) async {
    if (tracks.isEmpty) return const MediaTransferBatchResult([]);

    final directory = await _resolveDownloadDirectory();
    await directory.create(recursive: true);

    final results = <MediaTransferItemResult>[];
    for (final track in tracks) {
      final destination = File(
        directory.path + Platform.pathSeparator + _fileNameFor(track),
      );

      onProgress?.call(
        MediaTransferItemProgress(
          id: track.id,
          title: track.title,
          direction: MediaTransferDirection.downloadFromDesktop,
          status: MediaTransferItemStatus.queued,
          totalBytes: track.byteLength > 0 ? track.byteLength : null,
          destinationPath: destination.path,
        ),
      );

      try {
        final reusable = await destination.exists() &&
            track.byteLength > 0 &&
            await destination.length() == track.byteLength;

        if (!reusable) {
          onProgress?.call(
            MediaTransferItemProgress(
              id: track.id,
              title: track.title,
              direction: MediaTransferDirection.downloadFromDesktop,
              status: MediaTransferItemStatus.transferring,
              totalBytes: track.byteLength > 0 ? track.byteLength : null,
              destinationPath: destination.path,
            ),
          );
          await client.downloadTrack(
            track: track,
            destinationPath: destination.path,
            onProgress: (transferred, total) {
              onProgress?.call(
                MediaTransferItemProgress(
                  id: track.id,
                  title: track.title,
                  direction: MediaTransferDirection.downloadFromDesktop,
                  status: MediaTransferItemStatus.transferring,
                  bytesTransferred: transferred,
                  totalBytes: total ??
                      (track.byteLength > 0 ? track.byteLength : null),
                  destinationPath: destination.path,
                ),
              );
            },
          );
        }

        await libraryRepository.addPaths([destination.path]);
        final bytes = await destination.length();
        onProgress?.call(
          MediaTransferItemProgress(
            id: track.id,
            title: track.title,
            direction: MediaTransferDirection.downloadFromDesktop,
            status: MediaTransferItemStatus.completed,
            bytesTransferred: bytes,
            totalBytes: bytes,
            destinationPath: destination.path,
          ),
        );
        results.add(
          MediaTransferItemResult(
            id: track.id,
            title: track.title,
            direction: MediaTransferDirection.downloadFromDesktop,
            succeeded: true,
            destinationPath: destination.path,
          ),
        );
      } catch (error) {
        final message = error.toString();
        onProgress?.call(
          MediaTransferItemProgress(
            id: track.id,
            title: track.title,
            direction: MediaTransferDirection.downloadFromDesktop,
            status: MediaTransferItemStatus.failed,
            totalBytes: track.byteLength > 0 ? track.byteLength : null,
            destinationPath: destination.path,
            error: message,
          ),
        );
        results.add(
          MediaTransferItemResult(
            id: track.id,
            title: track.title,
            direction: MediaTransferDirection.downloadFromDesktop,
            succeeded: false,
            destinationPath: destination.path,
            error: message,
          ),
        );
      }
    }

    return MediaTransferBatchResult(List.unmodifiable(results));
  }

  @override
  Future<MediaTransferBatchResult> uploadLocalFiles(
    List<String> sourcePaths, {
    MediaTransferProgressCallback? onProgress,
  }) async {
    if (sourcePaths.isEmpty) return const MediaTransferBatchResult([]);

    final results = <MediaTransferItemResult>[];
    for (final rawPath in sourcePaths) {
      final file = File(rawPath);
      final path = file.absolute.path;
      final fileName = file.uri.pathSegments.isEmpty
          ? path
          : file.uri.pathSegments.last;
      final title = _titleFromFileName(fileName);

      if (!await file.exists()) {
        const error = '本地音频文件不存在';
        onProgress?.call(
          MediaTransferItemProgress(
            id: path,
            title: title,
            direction: MediaTransferDirection.uploadToDesktop,
            status: MediaTransferItemStatus.failed,
            error: error,
          ),
        );
        results.add(
          MediaTransferItemResult(
            id: path,
            title: title,
            direction: MediaTransferDirection.uploadToDesktop,
            succeeded: false,
            error: error,
          ),
        );
        continue;
      }

      final total = await file.length();
      onProgress?.call(
        MediaTransferItemProgress(
          id: path,
          title: title,
          direction: MediaTransferDirection.uploadToDesktop,
          status: MediaTransferItemStatus.queued,
          totalBytes: total,
        ),
      );

      try {
        onProgress?.call(
          MediaTransferItemProgress(
            id: path,
            title: title,
            direction: MediaTransferDirection.uploadToDesktop,
            status: MediaTransferItemStatus.transferring,
            totalBytes: total,
          ),
        );
        await client.uploadFile(
          sourcePath: path,
          remoteFileName: fileName,
          onProgress: (transferred, expected) {
            onProgress?.call(
              MediaTransferItemProgress(
                id: path,
                title: title,
                direction: MediaTransferDirection.uploadToDesktop,
                status: MediaTransferItemStatus.transferring,
                bytesTransferred: transferred,
                totalBytes: expected ?? total,
              ),
            );
          },
        );
        onProgress?.call(
          MediaTransferItemProgress(
            id: path,
            title: title,
            direction: MediaTransferDirection.uploadToDesktop,
            status: MediaTransferItemStatus.completed,
            bytesTransferred: total,
            totalBytes: total,
          ),
        );
        results.add(
          MediaTransferItemResult(
            id: path,
            title: title,
            direction: MediaTransferDirection.uploadToDesktop,
            succeeded: true,
          ),
        );
      } catch (error) {
        final message = error.toString();
        onProgress?.call(
          MediaTransferItemProgress(
            id: path,
            title: title,
            direction: MediaTransferDirection.uploadToDesktop,
            status: MediaTransferItemStatus.failed,
            totalBytes: total,
            error: message,
          ),
        );
        results.add(
          MediaTransferItemResult(
            id: path,
            title: title,
            direction: MediaTransferDirection.uploadToDesktop,
            succeeded: false,
            error: message,
          ),
        );
      }
    }

    return MediaTransferBatchResult(List.unmodifiable(results));
  }

  Future<Directory> _resolveDownloadDirectory() async {
    final configured = downloadDirectory;
    if (configured != null) return configured;
    final documents = await getApplicationDocumentsDirectory();
    return Directory(
      documents.path +
          Platform.pathSeparator +
          'LyricForge' +
          Platform.pathSeparator +
          'Downloads',
    );
  }

  String _fileNameFor(RemoteAudioTrack track) {
    final title = _safeFileName(track.title);
    final id = _safeFileName(track.id);
    final suffix = id.length > 8 ? id.substring(0, 8) : id;
    final format = track.format.trim().toLowerCase().isEmpty
        ? 'audio'
        : track.format.trim().toLowerCase();
    return '${title}_$suffix.$format';
  }

  String _titleFromFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  String _safeFileName(String value) {
    final sanitized = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return sanitized.isEmpty ? 'audio' : sanitized;
  }
}
