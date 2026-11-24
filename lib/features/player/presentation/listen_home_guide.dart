import '../../../core/onboarding/getting_started.dart';
import '../../../core/onboarding/getting_started_store.dart';
import '../domain/models/local_media_library_entry.dart';
import '../domain/models/local_media_metadata.dart';
import '../domain/models/mobile_getting_started.dart';
import '../domain/models/play_history.dart';
import 'screens/mobile_lyrics_screen.dart';
import 'widgets/now_playing_listener.dart';

/// The 开始使用 checklist on 听歌 (D-071): whether it shows, and how far the
/// user has got. 听歌 owns the card; this owns what the card remembers.
class ListenHomeGuide {
  ListenHomeGuide({this.store, required this.readOverrides});

  /// Where the choice to show the card lives; null hides it for good.
  final GettingStartedStore? store;

  /// The user's per-song overrides, which say which songs have lyrics.
  final Future<List<LocalMediaMetadata>> Function() readOverrides;

  GettingStartedPreferences _preferences = const GettingStartedPreferences();

  /// What was last read or remembered.
  GettingStartedPreferences get preferences => _preferences;

  /// How far someone with [entries] and [histories] has got: songs in the
  /// library, songs with lyrics, and whether one of those was played.
  static MobileGettingStartedProgress progressFrom({
    required Iterable<LocalMediaLibraryEntry> entries,
    required List<LocalMediaMetadata> overrides,
    required Iterable<PlayHistory> histories,
  }) {
    final songs = entries.toList(growable: false);
    final withLyrics = [
      for (final song in MobileLyricsSong.from(songs, overrides))
        if (song.hasLyrics) song,
    ];
    final lyricPaths = {
      for (final song in withLyrics) NowPlaying.pathKey(song.path),
    };
    return MobileGettingStartedProgress(
      songCount: songs.where((entry) => !entry.isMissing).length,
      lyricSongCount: withLyrics.length,
      lyricSong: withLyrics.isEmpty ? null : withLyrics.first.playbackItem,
      playedWithLyrics: histories.any(
        (history) => lyricPaths.contains(NowPlaying.pathKey(history.filePath)),
      ),
    );
  }

  /// Reads the saved choice and works out the progress; null while the card
  /// is hidden. The first time, someone with no songs gets the card and
  /// someone who already has some does not. Never throws: a broken checklist
  /// must not cost the user the page.
  Future<MobileGettingStartedProgress?> load({
    required List<LocalMediaLibraryEntry> entries,
    required List<PlayHistory> histories,
  }) async {
    final store = this.store;
    if (store == null) return null;
    try {
      final saved = await store.load() ?? const GettingStartedPreferences();
      final hasContent = entries.any((entry) => !entry.isMissing);
      final preferences = saved.decidedFor(hasContent: hasContent);
      if (preferences.visibility != saved.visibility) {
        await store.save(preferences);
      }
      _preferences = preferences;
      if (!preferences.showsCard) return null;
      return progressFrom(
        entries: entries,
        overrides: await readOverrides(),
        histories: histories,
      );
    } on Object {
      return null;
    }
  }

  /// Remembers that the card is [visibility]. When saving fails the choice
  /// is kept for this session and the card still behaves.
  Future<void> remember(GettingStartedVisibility visibility) async {
    _preferences = _preferences.copyWith(visibility: visibility);
    final store = this.store;
    if (store == null) return;
    try {
      await store.save(_preferences);
    } on Object {
      // Kept in memory; see above.
    }
  }
}
