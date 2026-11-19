import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/library_folder_settings.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/library_lyric_file_matcher.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/library_lyrics_auto_linker.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/library_lyrics_pairing.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/library_lyrics_unpair_action.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

void main() {
  const song = '/music/夜曲.mp3';
  final pairing = LibraryLyricsPairing(
    lyricPath: '/曲库/周杰伦 - 夜曲.lrc',
    projectId: 'p-1',
    reason: LibraryLyricMatchReason.artistAndTitle,
    createdProject: true,
    projectRevision: 1,
    previousStatus: ProjectStatus.draft,
    previousStage: ProcessingStage.none,
    fingerprint: '1:00000000',
    pairedAt: DateTime(2026, 11, 29),
  );

  late _Linker linker;
  late int changes;

  setUp(() {
    linker = _Linker();
    changes = 0;
  });

  Widget host() => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => unawaited(
            unpairLibraryLyrics(
              context,
              linker: linker,
              audioPath: song,
              songTitle: '夜曲',
              pairing: pairing,
              onChanged: () async => changes++,
            ),
          ),
          child: const Text('解除'),
        ),
      ),
    ),
  );

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('解除'));
    await tester.pumpAndSettle();
  }

  testWidgets('the dialog names the file and why it was paired', (
    tester,
  ) async {
    await openDialog(tester);

    expect(find.text('解除歌词配对？'), findsOneWidget);
    expect(find.text('周杰伦 - 夜曲.lrc'), findsOneWidget);
    expect(find.text('配对依据：文件名是“歌手 - 歌名”'), findsOneWidget);
    expect(find.textContaining('歌词文件本身不会删除'), findsOneWidget);
    expect(find.textContaining('「夜曲」的歌词是按文件名'), findsOneWidget);
  });

  testWidgets('cancelling changes nothing', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(linker.unpaired, isEmpty);
    expect(changes, 0);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('unpairing reloads and offers an undo that pairs again', (
    tester,
  ) async {
    linker.unpairResult = LibraryLyricsUnpairResult(
      LibraryLyricsUnpairOutcome.unpaired,
      pairing: pairing,
      removedProject: true,
    );
    await openDialog(tester);

    await tester.tap(find.text('解除配对'));
    await tester.pumpAndSettle();

    expect(linker.unpaired, [song]);
    expect(changes, 1);
    expect(find.text('已解除「夜曲」和「周杰伦 - 夜曲.lrc」的配对'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(linker.pairedAgain, [(song, pairing.lyricPath)]);
    expect(changes, 2);
    expect(find.text('已恢复「夜曲」的歌词配对'), findsOneWidget);
  });

  testWidgets('edited lyrics are reported, with nothing to undo', (
    tester,
  ) async {
    linker.unpairResult = LibraryLyricsUnpairResult(
      LibraryLyricsUnpairOutcome.editedSincePairing,
      pairing: pairing,
    );
    await openDialog(tester);

    await tester.tap(find.text('解除配对'));
    await tester.pumpAndSettle();

    expect(find.text('「夜曲」的歌词在配对后改过，为免丢失修改，没有解除'), findsOneWidget);
    expect(find.text('撤销'), findsNothing);
    expect(changes, 0);
  });

  testWidgets('a failure is shown instead of a silent no-op', (tester) async {
    linker.unpairError = const FormatException('磁盘已满');
    await openDialog(tester);

    await tester.tap(find.text('解除配对'));
    await tester.pumpAndSettle();

    expect(find.textContaining('解除配对失败'), findsOneWidget);
    expect(find.textContaining('磁盘已满'), findsOneWidget);
    expect(changes, 0);
  });
}

class _Linker implements LibraryLyricsAutoLinker {
  final List<String> unpaired = [];
  final List<(String, String)> pairedAgain = [];
  LibraryLyricsUnpairResult unpairResult = const LibraryLyricsUnpairResult(
    LibraryLyricsUnpairOutcome.notAutoPaired,
  );
  Exception? unpairError;

  @override
  Future<LibraryLyricsUnpairResult> unpair(String audioPath) async {
    unpaired.add(audioPath);
    final error = unpairError;
    if (error != null) throw error;
    return unpairResult;
  }

  @override
  Future<LibraryLyricsLinkResult> pairAgain(
    String audioPath,
    LibraryLyricsPairing pairing,
  ) async {
    pairedAgain.add((audioPath, pairing.lyricPath));
    return LibraryLyricsLinkResult(
      folder: LibraryFolder.none,
      linked: [
        LibraryLyricMatch(
          song: LibraryLyricSong(audioPath: audioPath, title: '夜曲'),
          lyricPath: pairing.lyricPath,
          reason: pairing.reason,
        ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
