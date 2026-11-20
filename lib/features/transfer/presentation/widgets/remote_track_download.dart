import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/models/media_transfer_queue.dart';
import 'remote_library_semantics.dart';

/// Where one desktop song stands on the phone, worked out once for the
/// track row's icon, progress bar, notice and screen-reader label (audit
/// T-03).
///
/// The row derived this from five booleans inside its build method, and the
/// icon, the progress bar and the notice each re-read the booleans in their
/// own order. A song that was on the phone but had a failed download still in
/// the queue could show a ✓ next to a red 下载失败. Now there is one [state]
/// and every part of the row asks it.
@immutable
class RemoteTrackDownload {
  const RemoteTrackDownload({
    required this.state,
    this.fraction,
    this.error,
  });

  /// The status of a track that the library already has as [localEntry]
  /// (when [downloaded]) and that the download queue holds as [queueItem].
  ///
  /// A finished queue item only counts while its file is still there;
  /// [fileExists] checks that and defaults to the real file system.
  factory RemoteTrackDownload.resolve({
    required bool downloaded,
    MediaTransferQueueItem? queueItem,
    bool Function(String path)? fileExists,
  }) {
    final status = queueItem?.status;
    final destination = queueItem?.destinationPath;
    final exists = fileExists ?? _fileExists;
    final completedFileExists = destination != null && exists(destination);
    final completed =
        status == MediaTransferQueueStatus.completed &&
        (downloaded || completedFileExists);

    final RemoteTrackDownloadState state;
    if (downloaded || completed) {
      state = RemoteTrackDownloadState.downloaded;
    } else if (status == MediaTransferQueueStatus.failed) {
      state = RemoteTrackDownloadState.failed;
    } else if (status == MediaTransferQueueStatus.completed) {
      state = RemoteTrackDownloadState.stale;
    } else if (status == MediaTransferQueueStatus.queued) {
      state = RemoteTrackDownloadState.queued;
    } else if (status == MediaTransferQueueStatus.transferring) {
      state = RemoteTrackDownloadState.transferring;
    } else {
      state = RemoteTrackDownloadState.none;
    }

    return RemoteTrackDownload(
      state: state,
      fraction: state == RemoteTrackDownloadState.transferring
          ? progressOf(queueItem)
          : null,
      error: state == RemoteTrackDownloadState.failed
          ? _trimmedOrNull(queueItem?.error)
          : null,
    );
  }

  final RemoteTrackDownloadState state;

  /// 0 to 1 while transferring with a known size, otherwise null.
  final double? fraction;

  /// The failure reason the queue recorded, when [state] is failed.
  final String? error;

  /// The share of [item] already copied, or null when its size is unknown.
  static double? progressOf(MediaTransferQueueItem? item) {
    final total = item?.totalBytes;
    if (item == null || total == null || total <= 0) return null;
    return (item.bytesTransferred / total).clamp(0.0, 1.0).toDouble();
  }

  /// The notice for a failed download without a recorded reason.
  static const String failedNotice = '下载失败，点击右侧重试';

  /// The notice for a finished download whose file is gone.
  static const String staleNotice = '本地文件已不存在，可重新下载';

  /// The download button's tooltip and action name.
  String get tooltip => RemoteLibrarySemantics.downloadTooltip(state);

  /// Whether the download button does anything.
  bool get canDownload => RemoteLibrarySemantics.canDownload(state);

  /// The progress bar under the title: while queued or copying.
  bool get showsProgress =>
      state == RemoteTrackDownloadState.queued ||
      state == RemoteTrackDownloadState.transferring;

  /// The progress bar's value; null makes it indeterminate, as it is while
  /// the song waits in the queue.
  double? get progressValue =>
      state == RemoteTrackDownloadState.transferring ? fraction : null;

  /// The download button shows a spinner instead of an icon.
  bool get showsSpinner => state == RemoteTrackDownloadState.transferring;

  /// The download button's icon when it is not a spinner.
  IconData get icon => switch (state) {
    RemoteTrackDownloadState.downloaded => Icons.download_done_rounded,
    RemoteTrackDownloadState.failed ||
    RemoteTrackDownloadState.stale => Icons.refresh_rounded,
    RemoteTrackDownloadState.queued => Icons.schedule_rounded,
    RemoteTrackDownloadState.transferring ||
    RemoteTrackDownloadState.none => Icons.download_rounded,
  };

  /// The small line under the title that explains a problem, or null.
  String? get notice => switch (state) {
    RemoteTrackDownloadState.failed => error ?? failedNotice,
    RemoteTrackDownloadState.stale => staleNotice,
    _ => null,
  };

  /// The [notice] reports a failure rather than a fact.
  bool get noticeIsError => state == RemoteTrackDownloadState.failed;

  /// This status as part of the row's screen-reader label.
  String? get semanticStatus => RemoteLibrarySemantics.downloadStatus(
    state,
    fraction: fraction,
    error: error,
  );

  static bool _fileExists(String path) => File(path).existsSync();

  static String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  @override
  bool operator ==(Object other) =>
      other is RemoteTrackDownload &&
      other.state == state &&
      other.fraction == fraction &&
      other.error == error;

  @override
  int get hashCode => Object.hash(state, fraction, error);

  @override
  String toString() =>
      'RemoteTrackDownload($state, fraction: $fraction, error: $error)';
}
