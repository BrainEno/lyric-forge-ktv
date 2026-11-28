import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_export_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/lyric_editor_document_controller.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/lyric_editor_dependencies.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/screens/lyric_editor_screen.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_editor_toolbar.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_line_jump.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_review_row.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/memory_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

/// D-067: 跳到行 from the keyboard on a desktop and from the menu on a phone.
void main() {
  Finder row(String text) => find.widgetWithText(LyricReviewRow, text);

  Future<LyricEditorDocumentController> open(
    WidgetTester tester, {
    Size size = const Size(1600, 900),
  }) async {
    final repository = MemoryProjectRepository();
    var project = await repository.createProject(name: 'Song');
    project = await repository.updateProject(
      project.copyWith(
        lyricDocument: LyricDocument(
          language: 'zh',
          lines: [
            for (var index = 0; index < 60; index++)
              LyricLine(
                text: 'line ${index + 1}',
                startTime: Duration(seconds: index * 4 + 1),
                endTime: Duration(seconds: index * 4 + 3),
              ),
          ],
        ),
        audioAsset: const AudioAsset(
          originalPath: 'song.wav',
          format: 'wav',
          duration: Duration(seconds: 260),
        ),
      ),
    );
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: LyricEditorScreen(
          projectId: project.id,
          dependencies: LyricEditorDependencies(
            projectRepository: repository,
            playbackSession: _FakePlaybackSession(),
            audioPlayer: _FakeAudioPlayer(),
            lyricFileExport: _FakeLyricFileExport(),
            lyricFileImport: LocalLyricFileImportService(),
            forcedAlignmentRunner: _noAlignment,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return Provider.of<LyricEditorDocumentController>(
      tester.element(find.byType(LyricReviewRow).first),
      listen: false,
    );
  }

  bool onScreen(WidgetTester tester, String text) {
    final finder = row(text);
    if (finder.evaluate().isEmpty) return false;
    final rect = tester.getRect(finder);
    final list = tester.getRect(find.byType(ListView).first);
    return rect.top >= list.top && rect.bottom <= list.bottom;
  }

  testWidgets('Ctrl+G, a row number and Enter select and show that row', (
    tester,
  ) async {
    final editor = await open(tester);
    await tester.tap(row('line 1'));
    // The row also listens for a double tap.
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(onScreen(tester, 'line 45'), isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(LyricJumpToLineDialog), findsOneWidget);

    await tester.enterText(find.byKey(LyricJumpToLineDialog.inputKey), '45');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(LyricJumpToLineDialog), findsNothing);
    expect(editor.selectedLineIndex, 44);
    expect(onScreen(tester, 'line 45'), isTrue);

    // The list has the keyboard again: ↓ moves on from the row jumped to.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(editor.selectedLineIndex, 45);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone finds 跳到行 in the menu and jumps by time', (
    tester,
  ) async {
    final editor = await open(tester, size: const Size(390, 844));
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(LyricEditorOverflowMenu.jumpToLineKey));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(LyricJumpToLineDialog.inputKey), '1:05');
    await tester.pump();
    await tester.tap(find.byKey(LyricJumpToLineDialog.confirmKey));
    await tester.pumpAndSettle();
    expect(editor.selectedLineIndex, 16);
    expect(onScreen(tester, 'line 17'), isTrue);
    // Jumping only shows the row; it does not open the row's sheet.
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<List<ForcedAlignedSpan>> _noAlignment({
  required String audioPath,
  required String text,
  required String language,
  required Duration audioDuration,
}) async => const [];

class _FakeAudioPlayer implements AudioPlayerService {
  @override
  PlaybackState get currentState => const PlaybackState.idle();

  @override
  Stream<PlaybackState> get stateStream => const Stream.empty();

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlaybackSession implements PlaybackSessionService {
  @override
  PlaybackSessionState get currentState => const PlaybackSessionState();

  @override
  Stream<PlaybackSessionState> get stateStream => const Stream.empty();

  @override
  PlaybackState get playbackState => const PlaybackState.idle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLyricFileExport implements LyricFileExportService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
