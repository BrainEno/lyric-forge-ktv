import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A phone cannot run the recognition models, so the lyric workbench —
/// recognition, projects, the lyric editor and the AI 识别 settings — is not
/// offered there (D-058). These screens are too heavy to build in a widget
/// test, so their gates are pinned in the source.
void main() {
  /// The source without whitespace, so formatting does not matter.
  String read(String path) =>
      File(path).readAsStringSync().replaceAll(RegExp(r'\s+'), '');
  String squash(String code) => code.replaceAll(RegExp(r'\s+'), '');
  Matcher containsSquashed(String code) => contains(squash(code));

  test('settings hide AI 识别 and the trial run on a phone', () {
    final source = read(
      'lib/features/settings/presentation/screens/settings_screen.dart',
    );
    expect(
      source,
      containsSquashed('final recognition = AppCapabilities.lyricWorkbench;'),
    );
    expect(source, containsSquashed('if (recognition) ...['));
    expect(
      source,
      containsSquashed('recognition ? settingsIntro : mobileSettingsIntro'),
    );
    final mobileIntro = RegExp(
      r"constStringmobileSettingsIntro='([^']*)';",
    ).firstMatch(source)!.group(1)!;
    expect(mobileIntro, isNot(containsSquashed('识别')));
  });

  test('quick play offers recognition only on a desktop', () {
    final source = read(
      'lib/features/player/presentation/screens/quick_play_screen.dart',
    );
    expect(
      source,
      containsSquashed(
        'onCreateProject: AppCapabilities.lyricWorkbench\n'
        '                    ? () => Navigator.pushNamed(context, Routes.import)\n'
        '                    : null,',
      ),
    );
  });

  test('the player hides the editor and project page on a phone', () {
    final source = read(
      'lib/features/player/presentation/screens/player_screen.dart',
    );
    expect(
      source,
      containsSquashed(
        'onOpenLyricEditor: AppCapabilities.lyricWorkbench\n'
        '              ? () => _openLyricEditor(project)\n'
        '              : null,',
      ),
    );
    expect(source, containsSquashed('if (widget.onOpenLyricEditor != null)'));
    expect(source, containsSquashed("if (AppCapabilities.lyricWorkbench)\n"));
  });

  test('lyrics added on a phone open in the player, not the editor', () {
    final source = read(
      'lib/features/player/presentation/widgets/'
      'local_song_lyrics_import_action.dart',
    );
    expect(source, containsSquashed('timed && workbench'));
    expect(source, containsSquashed('if (AppCapabilities.lyricWorkbench) {'));
  });

  test('the phone router sends workbench routes to 歌词 or the player', () {
    final router = read('lib/app/app_router.dart');
    for (final route in ['dashboard', 'import', 'review']) {
      expect(
        router,
        containsSquashed('case Routes.$route when listeningHome:'),
      );
    }
    expect(
      router,
      containsSquashed('final playerOnly =\n              listeningHome &&'),
    );
    expect(router, isNot(containsSquashed('lyricsHub')));
  });

  test('the phone 歌词 page has no recognition entry', () {
    final source = read(
      'lib/features/player/presentation/screens/mobile_lyrics_screen.dart',
    );
    expect(source, isNot(containsSquashed('Routes.import')));
    expect(source, isNot(containsSquashed('Routes.dashboard')));
    expect(source, isNot(containsSquashed('lyricEditorPath')));
    expect(source, containsSquashed('TransferEntry.open(context)'));
  });
}
