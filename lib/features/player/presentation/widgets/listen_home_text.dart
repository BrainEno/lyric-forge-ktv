import 'package:flutter/widgets.dart';

import 'player_bar_semantics.dart';

/// The words on 听歌 (D-041), shared by the page and its parts.
abstract final class ListenHomeText {
  static const String title = '听歌';
  static const String recentTitle = '最近播放';
  static const String libraryTitle = '音乐库';
  static const String playAllLabel = '播放全部';
  static const String shuffleLabel = '随机播放';
  static const String openLibraryLabel = '打开音乐库';
  static const String idleTitle = '放一张唱片吧';
  static const String noSongsMessage = '音乐库里还没有可以播放的歌曲。';
  static const String importLyricsLabel = '导入歌词';
  static const String importMediaLabel = '导入音频或视频';
  static const String transferLabel = '从电脑传歌';
  static const String openPlayerHint = PlayerBarSemantics.openHint;
  static const String recentLoading = '正在读取…';
  static const String recentEmpty = '播放过的歌曲会出现在这里。';
  static const String recentHint = '继续播放';
}

/// The keys tests and the shell find 听歌's parts by.
abstract final class ListenHomeKeys {
  static const Key hero = ValueKey('listen-home:hero');
  static const Key playAll = ValueKey('listen-home:play-all');
  static const Key shuffle = ValueKey('listen-home:shuffle');
  static const Key lyricsNudge = ValueKey('listen-home:lyrics-nudge');
  static const Key import = ValueKey('listen-home:import');
  static const Key idleImport = ValueKey('listen-home:idle-import');
  static const Key search = ValueKey('listen-home-search');

  /// The 最近播放 row for the play with [historyId].
  static Key recent(String historyId) =>
      ValueKey('listen-home:recent:$historyId');
}
