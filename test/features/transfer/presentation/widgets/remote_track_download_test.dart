import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_transfer_batch.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_transfer_queue.dart';
import 'package:lyric_forge_ktv/features/transfer/presentation/widgets/remote_library_semantics.dart';
import 'package:lyric_forge_ktv/features/transfer/presentation/widgets/remote_track_download.dart';

// RemoteTrackDownload is where a desktop song stands on the phone, worked out
// once for the track row (audit T-03). The row used to re-read five booleans
// in a different order for its icon, progress bar and notice.

MediaTransferQueueItem _item(
  MediaTransferQueueStatus status, {
  int bytesTransferred = 0,
  int? totalBytes,
  String? destinationPath,
  String? error,
}) {
  final at = DateTime.utc(2026, 12, 4);
  return MediaTransferQueueItem(
    id: 'track-1',
    direction: MediaTransferDirection.downloadFromDesktop,
    title: '晴天',
    status: status,
    createdAt: at,
    updatedAt: at,
    bytesTransferred: bytesTransferred,
    totalBytes: totalBytes,
    destinationPath: destinationPath,
    error: error,
  );
}

RemoteTrackDownload _resolve({
  bool downloaded = false,
  MediaTransferQueueItem? item,
  Set<String> files = const {},
}) {
  return RemoteTrackDownload.resolve(
    downloaded: downloaded,
    queueItem: item,
    fileExists: files.contains,
  );
}

void main() {
  group('resolve', () {
    test('a song neither on the phone nor queued is none', () {
      final download = _resolve();
      expect(download.state, RemoteTrackDownloadState.none);
      expect(download.fraction, isNull);
      expect(download.error, isNull);
    });

    test('a song in the library is downloaded whatever the queue says', () {
      for (final status in MediaTransferQueueStatus.values) {
        final download = _resolve(downloaded: true, item: _item(status));
        expect(
          download.state,
          RemoteTrackDownloadState.downloaded,
          reason: '$status',
        );
        // A stale failure in the queue no longer shows next to the ✓.
        expect(download.notice, isNull, reason: '$status');
        expect(download.showsProgress, isFalse, reason: '$status');
      }
    });

    test('a finished download counts while its file is there', () {
      final download = _resolve(
        item: _item(
          MediaTransferQueueStatus.completed,
          destinationPath: '/music/晴天.flac',
        ),
        files: {'/music/晴天.flac'},
      );
      expect(download.state, RemoteTrackDownloadState.downloaded);
    });

    test('a finished download whose file is gone is stale', () {
      final download = _resolve(
        item: _item(
          MediaTransferQueueStatus.completed,
          destinationPath: '/music/晴天.flac',
        ),
      );
      expect(download.state, RemoteTrackDownloadState.stale);
      expect(download.notice, RemoteTrackDownload.staleNotice);
      expect(download.noticeIsError, isFalse);
    });

    test('a finished download without a destination is stale', () {
      final download = _resolve(
        item: _item(MediaTransferQueueStatus.completed),
      );
      expect(download.state, RemoteTrackDownloadState.stale);
    });

    test('queued and transferring follow the queue', () {
      expect(
        _resolve(item: _item(MediaTransferQueueStatus.queued)).state,
        RemoteTrackDownloadState.queued,
      );
      expect(
        _resolve(item: _item(MediaTransferQueueStatus.transferring)).state,
        RemoteTrackDownloadState.transferring,
      );
    });

    test('a failure keeps the trimmed reason', () {
      final download = _resolve(
        item: _item(MediaTransferQueueStatus.failed, error: '  电脑已断开  '),
      );
      expect(download.state, RemoteTrackDownloadState.failed);
      expect(download.error, '电脑已断开');
      expect(download.notice, '电脑已断开');
      expect(download.noticeIsError, isTrue);
    });

    test('a failure without a reason says how to retry', () {
      for (final error in [null, '', '   ']) {
        final download = _resolve(
          item: _item(MediaTransferQueueStatus.failed, error: error),
        );
        expect(download.error, isNull, reason: '$error');
        expect(download.notice, RemoteTrackDownload.failedNotice);
      }
    });

    test('the reason is dropped once the song is no longer failed', () {
      final download = _resolve(
        item: _item(MediaTransferQueueStatus.queued, error: '电脑已断开'),
      );
      expect(download.error, isNull);
      expect(download.notice, isNull);
    });
  });

  group('progress', () {
    test('is the copied share while transferring', () {
      final download = _resolve(
        item: _item(
          MediaTransferQueueStatus.transferring,
          bytesTransferred: 25,
          totalBytes: 100,
        ),
      );
      expect(download.fraction, 0.25);
      expect(download.progressValue, 0.25);
      expect(download.showsProgress, isTrue);
      expect(download.showsSpinner, isTrue);
    });

    test('is unknown without a size', () {
      for (final total in [null, 0, -1]) {
        final download = _resolve(
          item: _item(
            MediaTransferQueueStatus.transferring,
            bytesTransferred: 10,
            totalBytes: total,
          ),
        );
        expect(download.fraction, isNull, reason: '$total');
        expect(download.progressValue, isNull);
        expect(download.showsProgress, isTrue);
      }
    });

    test('is clamped to 0..1', () {
      expect(
        RemoteTrackDownload.progressOf(
          _item(
            MediaTransferQueueStatus.transferring,
            bytesTransferred: 300,
            totalBytes: 100,
          ),
        ),
        1.0,
      );
      expect(
        RemoteTrackDownload.progressOf(
          _item(
            MediaTransferQueueStatus.transferring,
            bytesTransferred: -5,
            totalBytes: 100,
          ),
        ),
        0.0,
      );
      expect(RemoteTrackDownload.progressOf(null), isNull);
    });

    test('a queued song shows an indeterminate bar and no spinner', () {
      final download = _resolve(
        item: _item(
          MediaTransferQueueStatus.queued,
          bytesTransferred: 10,
          totalBytes: 100,
        ),
      );
      expect(download.showsProgress, isTrue);
      expect(download.progressValue, isNull);
      expect(download.fraction, isNull);
      expect(download.showsSpinner, isFalse);
    });

    test('no other state shows a bar or a spinner', () {
      for (final state in [
        RemoteTrackDownloadState.none,
        RemoteTrackDownloadState.failed,
        RemoteTrackDownloadState.stale,
        RemoteTrackDownloadState.downloaded,
      ]) {
        final download = RemoteTrackDownload(state: state);
        expect(download.showsProgress, isFalse, reason: '$state');
        expect(download.showsSpinner, isFalse, reason: '$state');
      }
    });
  });

  group('button', () {
    test('icons follow the state', () {
      expect(
        {
          for (final state in RemoteTrackDownloadState.values)
            state: RemoteTrackDownload(state: state).icon,
        },
        {
          RemoteTrackDownloadState.none: Icons.download_rounded,
          RemoteTrackDownloadState.queued: Icons.schedule_rounded,
          RemoteTrackDownloadState.transferring: Icons.download_rounded,
          RemoteTrackDownloadState.failed: Icons.refresh_rounded,
          RemoteTrackDownloadState.stale: Icons.refresh_rounded,
          RemoteTrackDownloadState.downloaded: Icons.download_done_rounded,
        },
      );
    });

    test('tooltip and availability come from the shared wording', () {
      for (final state in RemoteTrackDownloadState.values) {
        final download = RemoteTrackDownload(state: state);
        expect(download.tooltip, RemoteLibrarySemantics.downloadTooltip(state));
        expect(
          download.canDownload,
          RemoteLibrarySemantics.canDownload(state),
        );
      }
    });

    test('only a song that can be fetched again has a working button', () {
      final working = RemoteTrackDownloadState.values
          .where((state) => RemoteTrackDownload(state: state).canDownload)
          .toSet();
      expect(working, {
        RemoteTrackDownloadState.none,
        RemoteTrackDownloadState.failed,
        RemoteTrackDownloadState.stale,
      });
    });
  });

  group('semantics', () {
    test('the label status matches the row', () {
      final download = _resolve(
        item: _item(
          MediaTransferQueueStatus.transferring,
          bytesTransferred: 40,
          totalBytes: 100,
        ),
      );
      expect(download.semanticStatus, '正在下载 40%');
    });

    test('a failure reads its reason', () {
      final download = _resolve(
        item: _item(MediaTransferQueueStatus.failed, error: '空间不足'),
      );
      expect(download.semanticStatus, '下载失败：空间不足');
    });

    test('a song that is simply not on the phone adds nothing', () {
      expect(_resolve().semanticStatus, isNull);
    });
  });

  test('equal statuses compare equal', () {
    const a = RemoteTrackDownload(
      state: RemoteTrackDownloadState.transferring,
      fraction: 0.5,
    );
    const b = RemoteTrackDownload(
      state: RemoteTrackDownloadState.transferring,
      fraction: 0.5,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(
      a,
      isNot(
        const RemoteTrackDownload(
          state: RemoteTrackDownloadState.transferring,
          fraction: 0.6,
        ),
      ),
    );
    expect(a.toString(), contains('transferring'));
  });
}
