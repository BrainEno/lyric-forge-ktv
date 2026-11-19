import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/widgets/app_badge.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/playback_facts.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

PlaybackItem _item({
  String format = 'mp3',
  bool hasLyrics = false,
  String? projectId,
  Uri? streamUri,
}) {
  return PlaybackItem(
    id: 'song',
    title: '夜曲',
    audioAsset: AudioAsset(originalPath: '/music/song.$format', format: format),
    hasLyrics: hasLyrics,
    projectId: projectId,
    streamUri: streamUri,
  );
}

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

Finder _badge(String label) => find.byWidgetPredicate(
  (widget) => widget is AppBadge && widget.label == label,
);

void main() {
  group('PlaybackOrigin', () {
    test('a project id wins over a stream', () {
      final item = _item(
        projectId: 'p1',
        streamUri: Uri.parse('http://host/song'),
      );
      expect(PlaybackOrigin.of(item), PlaybackOrigin.project);
    });

    test('a stream without a project is the desktop library', () {
      final item = _item(streamUri: Uri.parse('http://host/song'));
      expect(PlaybackOrigin.of(item), PlaybackOrigin.remote);
    });

    test('anything else is local music', () {
      expect(PlaybackOrigin.of(_item()), PlaybackOrigin.local);
    });

    test('labels are Chinese', () {
      expect(PlaybackOrigin.local.label, '本地音乐');
      expect(PlaybackOrigin.remote.label, '桌面音乐库');
      expect(PlaybackOrigin.project.label, '歌词工程');
    });
  });

  group('PlaybackFactBadges.formatLabel', () {
    test('capitalises the format', () {
      expect(PlaybackFactBadges.formatLabel(_item(format: 'flac')), 'FLAC');
    });

    test('drops a leading dot and spaces', () {
      expect(PlaybackFactBadges.formatLabel(_item(format: ' .m4a ')), 'M4A');
    });

    test('falls back to a Chinese word', () {
      expect(
        PlaybackFactBadges.formatLabel(_item(format: '')),
        PlaybackFactBadges.unknownFormatLabel,
      );
    });
  });

  group('PlaybackFactBadges', () {
    testWidgets('shows the format and that lyrics exist', (tester) async {
      await _pump(tester, PlaybackFactBadges(item: _item(hasLyrics: true)));

      expect(_badge('MP3'), findsOneWidget);
      expect(_badge(PlaybackFactBadges.lyricsLabel), findsOneWidget);
      expect(_badge(PlaybackFactBadges.missingLyricsLabel), findsNothing);
      final lyrics = tester.widget<AppBadge>(
        _badge(PlaybackFactBadges.lyricsLabel),
      );
      expect(lyrics.tone, AppBadgeTone.success);
    });

    testWidgets('mentions missing lyrics by default', (tester) async {
      await _pump(tester, PlaybackFactBadges(item: _item()));

      expect(_badge(PlaybackFactBadges.missingLyricsLabel), findsOneWidget);
      final missing = tester.widget<AppBadge>(
        _badge(PlaybackFactBadges.missingLyricsLabel),
      );
      expect(missing.tone, AppBadgeTone.neutral);
    });

    testWidgets('can leave missing lyrics unsaid', (tester) async {
      await _pump(
        tester,
        PlaybackFactBadges(item: _item(), showMissingLyrics: false),
      );

      expect(find.byType(AppBadge), findsOneWidget);
      expect(_badge('MP3'), findsOneWidget);
    });

    testWidgets('never shows the old English origin words', (tester) async {
      for (final item in [
        _item(hasLyrics: true),
        _item(projectId: 'p1', hasLyrics: true),
        _item(streamUri: Uri.parse('http://host/song')),
      ]) {
        await _pump(tester, PlaybackFactBadges(item: item));
        for (final word in ['LOCAL', 'REMOTE', 'PROJECT', 'LYRICS', 'AUDIO']) {
          expect(_badge(word), findsNothing, reason: word);
        }
      }
    });
  });
}
