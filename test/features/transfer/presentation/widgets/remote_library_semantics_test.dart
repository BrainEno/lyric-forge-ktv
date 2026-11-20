import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transfer/presentation/widgets/remote_library_semantics.dart';

// The phone's view of the desktop library as a screen reader reads it
// (audit A-04): what each tile is, and whether the song is on the phone.

void main() {
  group('downloadTooltip', () {
    test('matches the button for every state', () {
      expect(
        {
          for (final state in RemoteTrackDownloadState.values)
            state: RemoteLibrarySemantics.downloadTooltip(state),
        },
        {
          RemoteTrackDownloadState.none: '下载到手机',
          RemoteTrackDownloadState.queued: '等待下载',
          RemoteTrackDownloadState.transferring: '正在下载',
          RemoteTrackDownloadState.failed: '重新下载',
          RemoteTrackDownloadState.stale: '重新下载',
          RemoteTrackDownloadState.downloaded: '已下载到手机',
        },
      );
    });
  });

  group('canDownload', () {
    test('only songs that are not on their way or already here', () {
      final allowed = RemoteTrackDownloadState.values
          .where(RemoteLibrarySemantics.canDownload)
          .toSet();
      expect(allowed, {
        RemoteTrackDownloadState.none,
        RemoteTrackDownloadState.failed,
        RemoteTrackDownloadState.stale,
      });
    });
  });

  group('downloadStatus', () {
    test('a song that is simply not here says nothing', () {
      expect(
        RemoteLibrarySemantics.downloadStatus(RemoteTrackDownloadState.none),
        isNull,
      );
    });

    test('a transfer says how far it is', () {
      expect(
        RemoteLibrarySemantics.downloadStatus(
          RemoteTrackDownloadState.transferring,
          fraction: 0.426,
        ),
        '正在下载 43%',
      );
      expect(
        RemoteLibrarySemantics.downloadStatus(
          RemoteTrackDownloadState.transferring,
        ),
        '正在下载',
      );
    });

    test('a failure carries its reason when there is one', () {
      expect(
        RemoteLibrarySemantics.downloadStatus(
          RemoteTrackDownloadState.failed,
          error: ' 桌面端已断开 ',
        ),
        '下载失败：桌面端已断开',
      );
      expect(
        RemoteLibrarySemantics.downloadStatus(
          RemoteTrackDownloadState.failed,
          error: '',
        ),
        '下载失败',
      );
    });

    test('the other states', () {
      expect(
        RemoteLibrarySemantics.downloadStatus(
          RemoteTrackDownloadState.downloaded,
        ),
        '已下载到手机',
      );
      expect(
        RemoteLibrarySemantics.downloadStatus(RemoteTrackDownloadState.queued),
        '等待下载',
      );
      expect(
        RemoteLibrarySemantics.downloadStatus(RemoteTrackDownloadState.stale),
        '本地文件已不存在，可重新下载',
      );
    });
  });

  group('trackTile', () {
    test('title, artist, album, format, lyrics and the download state', () {
      expect(
        RemoteLibrarySemantics.trackTile(
          title: '晴天',
          artist: '周杰伦',
          album: '叶惠美',
          format: 'flac',
          hasLyrics: true,
          state: RemoteTrackDownloadState.downloaded,
        ),
        '晴天，周杰伦，叶惠美，FLAC，有歌词，已下载到手机',
      );
    });

    test('missing artist and album are left out', () {
      expect(
        RemoteLibrarySemantics.trackTile(
          title: '录音',
          artist: null,
          album: '',
          format: 'mp3',
          hasLyrics: false,
          state: RemoteTrackDownloadState.none,
        ),
        '录音，MP3',
      );
    });

    test('a blank title is named', () {
      expect(
        RemoteLibrarySemantics.trackTile(
          title: ' ',
          artist: null,
          album: null,
          format: 'wav',
          hasLyrics: false,
          state: RemoteTrackDownloadState.queued,
        ),
        '未命名歌曲，WAV，等待下载',
      );
    });
  });

  group('groupCard', () {
    test('name and count', () {
      expect(
        RemoteLibrarySemantics.groupCard(name: '周杰伦', count: 12),
        '周杰伦，12 首',
      );
    });

    test('a blank name is named', () {
      expect(RemoteLibrarySemantics.groupCard(name: '', count: 1), '未知，1 首');
    });
  });
}
