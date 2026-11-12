import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/lyric_editor_document_controller.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_review_proposal.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/project_proofread_evidence.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_alignment_audio_guard.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/reference_alignment_restore_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/reference_alignment_provenance_builder.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/reference_alignment_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/reference_alignment_review.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_export_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/lyric_editor_dependencies.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/screens/lyric_editor_screen.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/memory_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

void main() {
  group('auto proofreading evidence routing', () {
    for (final mode in [
      'no reference',
      'matching reference',
      'unrelated reference',
    ]) {
      testWidgets('auto $mode reports evidence actually used', (tester) async {
        var calls = 0;
        String? path;
        final editor = await _openEditor(tester, ({
          required audioPath,
          required text,
          required language,
          required audioDuration,
        }) async {
          calls++;
          path = audioPath;
          return [];
        }, vocalPath: '/managed/vocals.wav');
        await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('智能校对 V2'));
        await tester.pumpAndSettle();
        if (mode != 'no reference') {
          await tester.ensureVisible(find.text('本次提供参考歌词'));
          await tester.tap(find.text('本次提供参考歌词'));
          await tester.pumpAndSettle();
        }
        final toggle = find.byKey(
          const ValueKey('forced_alignment_review_toggle'),
        );
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        final field = find.byKey(
          const ValueKey('secondary_asr_transcript_input'),
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, '[00:00.00] Human lyric');
        await tester.tap(find.text('继续'));
        await tester.pumpAndSettle();
        if (mode != 'no reference') {
          expect(find.byType(ReferenceAlignmentDialog), findsOneWidget);
          _submitReference(
            tester,
            mode == 'matching reference'
                ? 'Human lyric'
                : 'completely unrelated words',
          );
          await tester.pumpAndSettle();
        }
        expect(find.text('智能校对提案复核'), findsOneWidget);
        if (mode == 'matching reference') {
          expect(calls, 1);
          expect(path, '/managed/vocals.wav');
          expect(find.textContaining('对齐结果不完整'), findsOneWidget);
          expect(find.textContaining('第二份 ASR 转写稿未参与本次复核'), findsOneWidget);
        } else {
          expect(calls, 1);
          expect(path, '/managed/vocals.wav');
          expect(find.textContaining('已将第二份带时间戳的转写稿作为独立证据'), findsOneWidget);
          if (mode == 'unrelated reference') {
            expect(find.textContaining('自动策略因参考文本覆盖率低于 25%'), findsOneWidget);
            expect(find.textContaining('未用参考歌词替换草稿'), findsOneWidget);
          }
        }
        expect(editor.document!.lines.single.text, 'Human lyric');
        expect(editor.hasChanges, isFalse);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('automatic strategy validates secondary text before running', (
      tester,
    ) async {
      var calls = 0;
      final editor = await _openEditor(tester, ({
        required audioPath,
        required text,
        required language,
        required audioDuration,
      }) async {
        calls++;
        return [];
      });
      await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('智能校对 V2'));
      await tester.pumpAndSettle();
      final field = find.byKey(
        const ValueKey('secondary_asr_transcript_input'),
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, 'no timestamps');
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(find.textContaining('必须为每行都带时间戳'), findsOneWidget);
      expect(find.text('智能校对提案复核'), findsNothing);
      expect(editor.hasChanges, isFalse);
      expect(calls, 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('explicit reference timing application', () {
    Future<List<ForcedAlignedSpan>> align({
      required String audioPath,
      required String text,
      required String language,
      required Duration audioDuration,
    }) async => const [
      ForcedAlignedSpan(
        text: 'Human lyric',
        start: Duration(milliseconds: 500),
        end: Duration(milliseconds: 1200),
      ),
    ];

    testWidgets(
      'applies selected timing in memory and batch undo restores it',
      (tester) async {
        final guard = _ReferenceTimingGuard();
        final editor = await _openEditor(tester, align, timingGuard: guard);
        await _openReferenceEvidenceReview(tester, 'Human lyric');
        final checkbox = find.byKey(
          const ValueKey('accept_reference_timing_0'),
        );
        await tester.ensureVisible(checkbox);
        expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('应用所选（琥珀色'));
        await tester.pumpAndSettle();
        expect(
          editor.document!.lines.single.startTime,
          const Duration(milliseconds: 500),
        );
        final id = editor.document!.lines.single.id!;
        expect(
          (editor.document!.metadata['timingProvenance'] as Map)[id],
          'forcedAlignmentReference',
        );
        expect(editor.hasChanges, isTrue);
        expect(guard.verifyCalls, 3);
        await tester.tap(find.text('撤销').last);
        await tester.pumpAndSettle();
        expect(editor.document!.lines.single.startTime, Duration.zero);
        expect(editor.hasChanges, isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('changed audio after review refuses the entire selection', (
      tester,
    ) async {
      final guard = _ReferenceTimingGuard()..failVerifyAt = 2;
      final editor = await _openEditor(tester, align, timingGuard: guard);
      await _openReferenceEvidenceReview(tester, 'Human lyric');
      final checkbox = find.byKey(const ValueKey('accept_reference_timing_0'));
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('应用所选（琥珀色'));
      await tester.pumpAndSettle();
      expect(find.textContaining('对齐音频内容已变化'), findsOneWidget);
      expect(editor.document!.lines.single.startTime, Duration.zero);
      expect(editor.hasChanges, isFalse);
    });

    testWidgets(
      'failed capture presents evidence but disables timing selection',
      (tester) async {
        final guard = _ReferenceTimingGuard()
          ..captureStatus = ReferenceAlignmentAudioStatus.audioUnavailable;
        final editor = await _openEditor(tester, align, timingGuard: guard);
        await _openReferenceEvidenceReview(tester, 'Human lyric');
        final checkbox = find.byKey(
          const ValueKey('accept_reference_timing_0'),
        );
        await tester.ensureVisible(checkbox);
        expect(tester.widget<CheckboxListTile>(checkbox).onChanged, isNull);
        expect(find.textContaining('无法读取对齐音频'), findsOneWidget);
        expect(editor.hasChanges, isFalse);
      },
    );

    testWidgets(
      'changed audio immediately before commit refuses selected timing',
      (tester) async {
        final guard = _ReferenceTimingGuard()..failVerifyAt = 3;
        final editor = await _openEditor(tester, align, timingGuard: guard);
        await _openReferenceEvidenceReview(tester, 'Human lyric');
        final checkbox = find.byKey(
          const ValueKey('accept_reference_timing_0'),
        );
        await tester.ensureVisible(checkbox);
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('应用所选（琥珀色'));
        await tester.pumpAndSettle();
        expect(find.textContaining('对齐音频内容已变化'), findsOneWidget);
        expect(editor.document!.lines.single.startTime, Duration.zero);
        expect(editor.hasChanges, isFalse);
      },
    );
  });

  group('reference timing audition integration', () {
    Future<List<ForcedAlignedSpan>> align({
      required String audioPath,
      required String text,
      required String language,
      required Duration audioDuration,
    }) async => const [
      ForcedAlignedSpan(
        text: 'Human lyric',
        start: Duration(milliseconds: 500),
        end: Duration(milliseconds: 1200),
      ),
    ];
    final button = find.byKey(const ValueKey('preview_reference_timing_0'));

    testWidgets(
      'plays absolute range on verified vocal and stops when dialog closes',
      (tester) async {
        final guard = _ReferenceTimingGuard();
        final audio = _PreviewAudioPlayer(source: AudioSourceType.vocals);
        final session = _PreviewPlaybackSession();
        final document = _document(
          'Human lyric',
        ).copyWith(globalOffset: const Duration(milliseconds: 300));
        final editor = await _openEditor(
          tester,
          align,
          initialDocument: document,
          vocalPath: '/vocal.wav',
          timingGuard: guard,
          previewAudio: audio,
          previewSession: session,
        );
        await _openReferenceEvidenceReview(tester, 'Human lyric');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(session.seeks, [const Duration(milliseconds: 250)]);
        expect(audio.playCalls, 1);
        expect(guard.verifyCalls, 2);
        expect(editor.document!.lines.single.startTime, Duration.zero);
        expect(editor.hasChanges, isFalse);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(audio.pauseCalls, 1);
        expect(editor.hasChanges, isFalse);
      },
    );

    testWidgets(
      'same project playing a different stem is refused without queue changes',
      (tester) async {
        final guard = _ReferenceTimingGuard();
        final audio = _PreviewAudioPlayer(source: AudioSourceType.original);
        final session = _PreviewPlaybackSession();
        final editor = await _openEditor(
          tester,
          align,
          vocalPath: '/vocal.wav',
          timingGuard: guard,
          previewAudio: audio,
          previewSession: session,
        );
        await _openReferenceEvidenceReview(tester, 'Human lyric');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.textContaining('播放器音源与对齐音源不同'), findsOneWidget);
        expect(session.seeks, isEmpty);
        expect(audio.playCalls, 0);
        expect(session.playItemCalls, 0);
        expect(editor.hasChanges, isFalse);
      },
    );

    testWidgets(
      'changed audio hash after review blocks audition without seeking',
      (tester) async {
        final guard = _ReferenceTimingGuard()..failVerifyAt = 2;
        final audio = _PreviewAudioPlayer(source: AudioSourceType.vocals);
        final session = _PreviewPlaybackSession();
        await _openEditor(
          tester,
          align,
          vocalPath: '/vocal.wav',
          timingGuard: guard,
          previewAudio: audio,
          previewSession: session,
        );
        await _openReferenceEvidenceReview(tester, 'Human lyric');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.textContaining('对齐音频内容已变化'), findsOneWidget);
        expect(session.seeks, isEmpty);
        expect(audio.playCalls, 0);
      },
    );

    testWidgets('closing during seek prevents late playback', (tester) async {
      final guard = _ReferenceTimingGuard();
      final audio = _PreviewAudioPlayer(source: AudioSourceType.vocals);
      final session = _PreviewPlaybackSession()..seekGate = Completer<void>();
      await _openEditor(
        tester,
        align,
        vocalPath: '/vocal.wav',
        timingGuard: guard,
        previewAudio: audio,
        previewSession: session,
      );
      await _openReferenceEvidenceReview(tester, 'Human lyric');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(session.seeks, [const Duration(milliseconds: 250)]);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      session.seekGate!.complete();
      await tester.pumpAndSettle();
      expect(audio.playCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('changing source during seek refuses late playback', (
      tester,
    ) async {
      final audio = _PreviewAudioPlayer(source: AudioSourceType.vocals);
      final session = _PreviewPlaybackSession()..seekGate = Completer<void>();
      await _openEditor(
        tester,
        align,
        vocalPath: '/vocal.wav',
        timingGuard: _ReferenceTimingGuard(),
        previewAudio: audio,
        previewSession: session,
      );
      await _openReferenceEvidenceReview(tester, 'Human lyric');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      audio.state = audio.state.copyWith(
        currentSource: AudioSourceType.original,
      );
      session.seekGate!.complete();
      await tester.pumpAndSettle();
      expect(audio.playCalls, 0);
      expect(find.textContaining('试听失败'), findsOneWidget);
    });

    testWidgets('closing while play starts pauses the owned late playback', (
      tester,
    ) async {
      final audio = _PreviewAudioPlayer(source: AudioSourceType.vocals)
        ..playGate = Completer<void>();
      final session = _PreviewPlaybackSession();
      await _openEditor(
        tester,
        align,
        vocalPath: '/vocal.wav',
        timingGuard: _ReferenceTimingGuard(),
        previewAudio: audio,
        previewSession: session,
      );
      await _openReferenceEvidenceReview(tester, 'Human lyric');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(audio.playCalls, 1);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      audio.playGate!.complete();
      await tester.pumpAndSettle();
      expect(audio.pauseCalls, 1);
      expect(audio.state.isPlaying, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'changing stem after starting does not pause another source on close',
      (tester) async {
        final audio = _PreviewAudioPlayer(source: AudioSourceType.vocals);
        final session = _PreviewPlaybackSession();
        await _openEditor(
          tester,
          align,
          vocalPath: '/vocal.wav',
          timingGuard: _ReferenceTimingGuard(),
          previewAudio: audio,
          previewSession: session,
        );
        await _openReferenceEvidenceReview(tester, 'Human lyric');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        audio.state = audio.state.copyWith(
          currentSource: AudioSourceType.original,
        );
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(audio.pauseCalls, 0);
      },
    );
  });

  group('reference forced-alignment evidence', () {
    testWidgets(
      'reference evidence reaches review without changing the editor',
      (tester) async {
        String? calledText;
        String? path;
        final editor = await _openEditor(tester, ({
          required audioPath,
          required text,
          required language,
          required audioDuration,
        }) async {
          calledText = text;
          path = audioPath;
          return const [
            ForcedAlignedSpan(
              text: 'Human lyric',
              start: Duration(milliseconds: 500),
              end: Duration(milliseconds: 1200),
            ),
          ];
        }, vocalPath: '/managed/vocals.wav');
        await _openReferenceEvidenceReview(tester, 'Human lyric');
        expect(calledText, 'Human lyric');
        expect(path, '/managed/vocals.wav');
        expect(
          find.textContaining('forcedAlignment(reference)'),
          findsOneWidget,
        );
        expect(
          find.textContaining('对齐时间（绝对音频时间）：0.50 s – 1.20 s'),
          findsOneWidget,
        );
        expect(find.textContaining('音源尚未通过校验，暂不可采纳'), findsOneWidget);
        expect(editor.document!.lines.single.startTime, Duration.zero);
        expect(editor.hasChanges, isFalse);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(editor.document!.lines.single.startTime, Duration.zero);
        expect(editor.hasChanges, isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'invalid alignment explains failure without presenting partial evidence',
      (tester) async {
        final editor = await _openEditor(
          tester,
          ({
            required audioPath,
            required text,
            required language,
            required audioDuration,
          }) async => const [
            ForcedAlignedSpan(
              text: 'wrong',
              start: Duration.zero,
              end: Duration(seconds: 1),
            ),
          ],
        );
        await _openReferenceEvidenceReview(tester, 'Human lyric');
        expect(find.textContaining('对齐片段与参考歌词不匹配'), findsOneWidget);
        expect(find.textContaining('已保留普通参考校对提案'), findsOneWidget);
        expect(find.textContaining('forcedAlignment(reference)'), findsNothing);
        expect(editor.hasChanges, isFalse);
      },
    );

    testWidgets('edit during reference alignment discards the stale proposal', (
      tester,
    ) async {
      final pending = Completer<List<ForcedAlignedSpan>>();
      final editor = await _openEditor(
        tester,
        ({
          required audioPath,
          required text,
          required language,
          required audioDuration,
        }) => pending.future,
      );
      await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('智能校对 V2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('参考歌词优先'));
      await tester.pumpAndSettle();
      final toggle = find.byKey(
        const ValueKey('forced_alignment_review_toggle'),
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      _submitReference(tester, 'Human lyric');
      await tester.pump();
      editor.updateLine(
        0,
        editor.document!.lines.single.copyWith(text: 'Edited while aligning'),
      );
      pending.complete(const [
        ForcedAlignedSpan(
          text: 'Human lyric',
          start: Duration(milliseconds: 500),
          end: Duration(milliseconds: 1200),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.textContaining('原提案已丢弃'), findsOneWidget);
      expect(find.text('智能校对提案复核'), findsNothing);
      expect(editor.document!.lines.single.text, 'Edited while aligning');
    });
  });

  group('project evidence routing', () {
    testWidgets(
      'verified evidence reaches review without modifying the draft',
      (tester) async {
        var calls = 0;
        final editor = await _openEditor(
          tester,
          _emptyAlignment,
          evidenceLoader:
              ({
                required projectId,
                required expectedProjectRevision,
                required draft,
              }) async {
                calls++;
                expect(draft.lines.single.text, 'Human lyric');
                return ProjectProofreadEvidenceResult.available(
                  secondary: _document('different lyric'),
                  secondaryEngine: 'whisper.cpp-large-v3',
                  capturedAtUtc: DateTime.utc(2026),
                );
              },
        );
        await _selectProjectEvidence(tester);
        expect(calls, 1);
        expect(find.text('智能校对提案复核'), findsOneWidget);
        expect(
          find.textContaining('工程独立第二稿：whisper.cpp-large-v3'),
          findsOneWidget,
        );
        expect(editor.document!.lines.single.text, 'Human lyric');
        expect(editor.hasChanges, isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('failed verification is explained and never opens review', (
      tester,
    ) async {
      final editor = await _openEditor(
        tester,
        _emptyAlignment,
        evidenceLoader:
            ({
              required projectId,
              required expectedProjectRevision,
              required draft,
            }) async => const ProjectProofreadEvidenceResult.unavailable(
              ProjectProofreadEvidenceStatus.audioChanged,
            ),
      );
      await _selectProjectEvidence(tester);
      expect(find.textContaining('识别音频与快照不一致'), findsOneWidget);
      expect(find.text('智能校对提案复核'), findsNothing);
      expect(editor.hasChanges, isFalse);
    });

    testWidgets('edit during verification discards the stale result', (
      tester,
    ) async {
      final pending = Completer<ProjectProofreadEvidenceResult>();
      final editor = await _openEditor(
        tester,
        _emptyAlignment,
        evidenceLoader:
            ({
              required projectId,
              required expectedProjectRevision,
              required draft,
            }) => pending.future,
      );
      await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('智能校对 V2'));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('project_asr_evidence_toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.tap(find.text('继续'));
      await tester.pump();
      editor.updateLine(
        0,
        editor.document!.lines.single.copyWith(text: 'New edit'),
      );
      pending.complete(
        ProjectProofreadEvidenceResult.available(
          secondary: _document('other'),
          secondaryEngine: 'whisper.cpp-large-v3',
          capturedAtUtc: DateTime.utc(2026),
        ),
      );
      await tester.pumpAndSettle();
      expect(editor.document!.lines.single.text, 'New edit');
      expect(find.textContaining('原提案已丢弃'), findsOneWidget);
      expect(find.text('智能校对提案复核'), findsNothing);
    });
  });

  group('reference proofreading revision guards', () {
    for (final action in ['参考歌词纠正', '逐行智能纠错（保留时间戳）']) {
      testWidgets('$action discards an edit made during reference input', (
        tester,
      ) async {
        final editor = await _openEditor(tester, _emptyAlignment);
        await _openReferenceFlow(tester, action);
        editor.updateLine(
          0,
          editor.document!.lines.single.copyWith(text: 'New edit'),
        );
        await tester.pump();
        _submitReference(tester, 'Human lyric');
        await tester.pumpAndSettle();
        expect(editor.document!.lines.single.text, 'New edit');
        expect(editor.canUndo, isTrue);
        expect(find.textContaining('原提案已丢弃'), findsOneWidget);
        expect(find.byType(ReferenceAlignmentReviewSheet), findsNothing);
        expect(find.text('导入独立 ASR 时间证据'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$action rejects edit followed by undo', (tester) async {
        final editor = await _openEditor(tester, _emptyAlignment);
        await _openReferenceFlow(tester, action);
        editor.updateLine(
          0,
          editor.document!.lines.single.copyWith(text: 'temporary'),
        );
        expect(editor.undo().applied, isTrue);
        _submitReference(tester, 'Human lyric');
        await tester.pumpAndSettle();
        expect(editor.document!.lines.single.text, 'Human lyric');
        expect(editor.canRedo, isTrue);
        expect(find.textContaining('原提案已丢弃'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('alignment review cannot overwrite later edits', (
      tester,
    ) async {
      final editor = await _openEditor(tester, _emptyAlignment);
      await _openReferenceFlow(tester, '参考歌词纠正');
      _submitReference(tester, 'Human lyric');
      await tester.pumpAndSettle();
      expect(find.byType(ReferenceAlignmentReviewSheet), findsOneWidget);
      editor.updateLine(
        0,
        editor.document!.lines.single.copyWith(
          text: 'Edited during alignment review',
        ),
      );
      await tester.pump();
      Navigator.of(
        tester.element(find.byType(ReferenceAlignmentReviewSheet)),
      ).pop(
        const ReferenceAlignmentReviewDecision(
          acceptedReferenceIndices: {},
          acceptedMissingReferenceIndices: {},
          overriddenAsrLineIndices: {},
          applyReferenceTiming: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        editor.document!.lines.single.text,
        'Edited during alignment review',
      );
      expect(editor.alignmentSnapshot, isNull);
      expect(find.textContaining('原提案已丢弃'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'proofreading discards edits while timing evidence dialog is open',
      (tester) async {
        final editor = await _openEditor(tester, _emptyAlignment);
        await _openReferenceFlow(tester, '逐行智能纠错（保留时间戳）');
        _submitReference(tester, 'Human lyrics');
        await tester.pumpAndSettle();
        expect(find.text('导入独立 ASR 时间证据'), findsOneWidget);
        editor.setLineReviewed(0, reviewed: true);
        await tester.tap(find.text('跳过校时'));
        await tester.pumpAndSettle();
        expect(editor.document!.lines.single.text, 'Human lyric');
        expect(find.text('参考歌词智能纠错'), findsNothing);
        expect(find.textContaining('原提案已丢弃'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    for (final withEvidence in [false, true]) {
      testWidgets(
        'proofreading review discards edits with evidence=$withEvidence',
        (tester) async {
          final editor = await _openEditor(
            tester,
            _emptyAlignment,
            initialDocument: _document('Hello word'),
          );
          await _openReferenceFlow(tester, '逐行智能纠错（保留时间戳）');
          _submitReference(tester, 'Hello world');
          await tester.pumpAndSettle();
          final timingTitle = find.text('导入独立 ASR 时间证据');
          if (withEvidence) {
            Navigator.of(
              tester.element(timingTitle),
            ).pop(_document('Hello world'));
          } else {
            await tester.tap(find.text('跳过校时'));
          }
          await tester.pumpAndSettle();
          final title = find.text(withEvidence ? '参考歌词纠错与校时复核' : '参考歌词智能纠错');
          expect(title, findsOneWidget);
          editor.updateLine(
            0,
            editor.document!.lines.single.copyWith(
              text: 'Changed during proofreading review',
            ),
          );
          await tester.pump();
          Navigator.of(tester.element(title)).pop(<int>{0});
          await tester.pumpAndSettle();
          expect(
            editor.document!.lines.single.text,
            'Changed during proofreading review',
          );
          expect(editor.alignmentSnapshot, isNull);
          expect(find.textContaining('原提案已丢弃'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('unchanged text-only review applies and can be undone', (
      tester,
    ) async {
      final editor = await _openEditor(
        tester,
        _emptyAlignment,
        initialDocument: _document('Hello word'),
      );
      await _openReferenceFlow(tester, '逐行智能纠错（保留时间戳）');
      _submitReference(tester, 'Hello world');
      await tester.pumpAndSettle();
      await tester.tap(find.text('跳过校时'));
      await tester.pumpAndSettle();
      final title = find.text('参考歌词智能纠错');
      expect(title, findsOneWidget);
      Navigator.of(tester.element(title)).pop(<int>{0});
      await tester.pumpAndSettle();
      expect(editor.document!.lines.single.text, 'Hello world');
      expect(editor.document!.lines.single.startTime, Duration.zero);
      expect(editor.undo().applied, isTrue);
      expect(editor.document!.lines.single.text, 'Hello word');
      expect(editor.redo().applied, isTrue);
      expect(editor.document!.lines.single.text, 'Hello world');
      expect(tester.takeException(), isNull);
    });

    testWidgets('selection changes alone do not invalidate reference review', (
      tester,
    ) async {
      final editor = await _openEditor(
        tester,
        _emptyAlignment,
        initialDocument: _document('Hello word'),
      );
      await _openReferenceFlow(tester, '逐行智能纠错（保留时间戳）');
      editor.select(null);
      _submitReference(tester, 'Hello world');
      await tester.pumpAndSettle();
      expect(find.text('导入独立 ASR 时间证据'), findsOneWidget);
      await tester.tap(find.text('跳过校时'));
      await tester.pumpAndSettle();
      expect(find.text('参考歌词智能纠错'), findsOneWidget);
      expect(find.textContaining('原提案已丢弃'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final changeDuringConfirmation in [false, true]) {
      testWidgets(
        'alignment timeline confirmation respects revision: edit=$changeDuringConfirmation',
        (tester) async {
          final editor = await _openEditor(tester, _emptyAlignment);
          await _openReferenceFlow(tester, '参考歌词纠正');
          Navigator.of(
            tester.element(find.byType(ReferenceAlignmentDialog)),
          ).pop(
            const ReferenceLyricInput(
              lines: [
                ReferenceLyricLine(
                  text: 'Human lyric',
                  startTime: Duration(seconds: 4),
                  endTime: Duration(seconds: 5),
                ),
              ],
              timed: true,
              format: 'lrc',
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(ReferenceAlignmentReviewSheet), findsOneWidget);
          Navigator.of(
            tester.element(find.byType(ReferenceAlignmentReviewSheet)),
          ).pop(
            const ReferenceAlignmentReviewDecision(
              acceptedReferenceIndices: {},
              acceptedMissingReferenceIndices: {},
              overriddenAsrLineIndices: {},
              applyReferenceTiming: true,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('这次对齐引入了时间轴冲突'), findsOneWidget);
          if (changeDuringConfirmation) {
            editor.updateLine(
              0,
              editor.document!.lines.single.copyWith(
                text: 'Edited at confirmation',
              ),
            );
            await tester.pump();
          }
          await tester.tap(find.text('保留并检查'));
          await tester.pumpAndSettle();
          if (changeDuringConfirmation) {
            expect(
              editor.document!.lines.single.text,
              'Edited at confirmation',
            );
            expect(editor.document!.lines.single.startTime, Duration.zero);
            expect(editor.alignmentSnapshot, isNull);
            expect(find.textContaining('原提案已丢弃'), findsOneWidget);
          } else {
            expect(
              editor.document!.lines.single.startTime,
              const Duration(seconds: 4),
            );
            expect(editor.alignmentSnapshot, isNotNull);
            final backup =
                editor.document!.metadata[kReferenceAlignmentBackupKey] as Map;
            expect(backup['lineCount'], 1);
            final provenance =
                editor.document!.metadata[ReferenceAlignmentProvenanceBuilder
                        .metadataKey]
                    as Map;
            expect(provenance['timingUpdatedCount'], 1);
            expect(editor.undo().applied, isTrue);
            expect(editor.document!.lines.single.startTime, Duration.zero);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('reference correction writes provenance only after review', (
      tester,
    ) async {
      final editor = await _openEditor(
        tester,
        _emptyAlignment,
        initialDocument: _document('Hello word'),
      );
      await _openReferenceFlow(tester, '参考歌词纠正');
      _submitReference(tester, 'Hello world');
      await tester.pumpAndSettle();
      expect(find.byType(ReferenceAlignmentReviewSheet), findsOneWidget);
      expect(
        editor.document!.metadata.containsKey(kReferenceAlignmentBackupKey),
        isFalse,
      );
      Navigator.of(
        tester.element(find.byType(ReferenceAlignmentReviewSheet)),
      ).pop(
        const ReferenceAlignmentReviewDecision(
          acceptedReferenceIndices: {0},
          acceptedMissingReferenceIndices: {},
          overriddenAsrLineIndices: {},
          applyReferenceTiming: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(editor.document!.lines.single.text, 'Hello world');
      expect(editor.document!.lines.single.startTime, Duration.zero);
      final backup =
          editor.document!.metadata[kReferenceAlignmentBackupKey] as Map;
      expect((backup['document'] as Map)['lines'], isNotEmpty);
      final provenance =
          editor.document!.metadata[ReferenceAlignmentProvenanceBuilder
                  .metadataKey]
              as Map;
      expect(provenance['appliedCorrectionCount'], 1);
      expect(editor.undo().applied, isTrue);
      expect(editor.document!.lines.single.text, 'Hello word');
      expect(
        editor.document!.metadata.containsKey(kReferenceAlignmentBackupKey),
        isFalse,
      );
      expect(editor.redo().applied, isTrue);
      expect(editor.document!.lines.single.text, 'Hello world');
      expect(
        editor.document!.metadata.containsKey(kReferenceAlignmentBackupKey),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('rejecting timeline warning never commits backup or changes', (
      tester,
    ) async {
      final editor = await _openEditor(tester, _emptyAlignment);
      await _openReferenceFlow(tester, '参考歌词纠正');
      Navigator.of(tester.element(find.byType(ReferenceAlignmentDialog))).pop(
        const ReferenceLyricInput(
          lines: [
            ReferenceLyricLine(
              text: 'Human lyric',
              startTime: Duration(seconds: 4),
              endTime: Duration(seconds: 5),
            ),
          ],
          timed: true,
          format: 'lrc',
        ),
      );
      await tester.pumpAndSettle();
      Navigator.of(
        tester.element(find.byType(ReferenceAlignmentReviewSheet)),
      ).pop(
        const ReferenceAlignmentReviewDecision(
          acceptedReferenceIndices: {},
          acceptedMissingReferenceIndices: {},
          overriddenAsrLineIndices: {},
          applyReferenceTiming: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('这次对齐引入了时间轴冲突'), findsOneWidget);
      await tester.tap(find.text('撤销本次对齐'));
      await tester.pumpAndSettle();
      expect(editor.document!.lines.single.startTime, Duration.zero);
      expect(
        editor.document!.metadata.containsKey(kReferenceAlignmentBackupKey),
        isFalse,
      );
      expect(editor.alignmentSnapshot, isNull);
      expect(editor.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposed editor ignores a pending reference input', (
      tester,
    ) async {
      await _openEditor(tester, _emptyAlignment);
      await _openReferenceFlow(tester, '参考歌词纠正');
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('delayed alignment discards edits and blocks a second run', (
    tester,
  ) async {
    final pending = Completer<List<ForcedAlignedSpan>>();
    var calls = 0;
    final editor = await _openEditor(tester, ({
      required audioPath,
      required text,
      required language,
      required audioDuration,
    }) {
      calls++;
      return pending.future;
    });
    await _startAlignment(tester);
    expect(calls, 1);
    await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('智能校对 V2'), findsNothing);
    editor.updateLine(
      0,
      editor.document!.lines.single.copyWith(text: 'New manual edit'),
    );
    await tester.pump();
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(editor.document!.lines.single.text, 'New manual edit');
    expect(editor.canUndo, isTrue);
    expect(find.textContaining('原提案已丢弃'), findsOneWidget);
    expect(find.text('智能校对提案复核'), findsNothing);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forced alignment uses the imported vocal path', (tester) async {
    String? usedPath;
    await _openEditor(tester, ({
      required audioPath,
      required text,
      required language,
      required audioDuration,
    }) async {
      usedPath = audioPath;
      return [];
    }, vocalPath: '/managed/人声.wav');
    await _startAlignment(tester);
    expect(usedPath, '/managed/人声.wav');
    expect(find.text('智能校对提案复核'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forced alignment falls back to original when no vocal exists', (
    tester,
  ) async {
    String? usedPath;
    await _openEditor(tester, ({
      required audioPath,
      required text,
      required language,
      required audioDuration,
    }) async {
      usedPath = audioPath;
      return [];
    });
    await _startAlignment(tester);
    expect(usedPath, 'song.wav');
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit then undo still invalidates a delayed result', (
    tester,
  ) async {
    final pending = Completer<List<ForcedAlignedSpan>>();
    final editor = await _openEditor(
      tester,
      ({
        required audioPath,
        required text,
        required language,
        required audioDuration,
      }) => pending.future,
    );
    await _startAlignment(tester);
    editor.updateLine(
      0,
      editor.document!.lines.single.copyWith(text: 'temporary'),
    );
    editor.undo();
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(editor.document!.lines.single.text, 'Human lyric');
    expect(editor.canRedo, isTrue);
    expect(find.textContaining('原提案已丢弃'), findsOneWidget);
    expect(find.text('智能校对提案复核'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changes while review is open block application', (tester) async {
    final editor = await _openEditor(tester, _emptyAlignment);
    await _startAlignment(tester);
    expect(find.text('智能校对提案复核'), findsOneWidget);
    editor.updateLine(
      0,
      editor.document!.lines.single.copyWith(text: 'Changed during review'),
    );
    await tester.pump();
    Navigator.of(tester.element(find.text('智能校对提案复核'))).pop(
      LyricProofreadV2Selection(
        acceptedProposalIndices: {0},
        restoredDraftIndices: {},
      ),
    );
    await tester.pumpAndSettle();
    expect(editor.document!.lines.single.text, 'Changed during review');
    expect(editor.canUndo, isTrue);
    expect(find.textContaining('原提案已丢弃'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late alignment after disposal does not access disposed state', (
    tester,
  ) async {
    final pending = Completer<List<ForcedAlignedSpan>>();
    await _openEditor(
      tester,
      ({
        required audioPath,
        required text,
        required language,
        required audioDuration,
      }) => pending.future,
    );
    await _startAlignment(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('智能校对提案复核'), findsNothing);
  });

  testWidgets('a change in the options dialog aborts before running', (
    tester,
  ) async {
    var calls = 0;
    final editor = await _openEditor(tester, ({
      required audioPath,
      required text,
      required language,
      required audioDuration,
    }) async {
      calls++;
      return [];
    });
    await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('智能校对 V2'));
    await tester.pumpAndSettle();
    editor.setLineReviewed(0, reviewed: true);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.textContaining('原提案已丢弃'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unchanged reference proposal applies and remains undoable', (
    tester,
  ) async {
    final editor = await _openEditor(tester, _emptyAlignment);
    await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('智能校对 V2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('参考歌词优先'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    editor.select(null);
    Navigator.of(tester.element(find.byType(ReferenceAlignmentDialog))).pop(
      ReferenceLyricInput(
        lines: [
          ReferenceLyricLine(
            text: 'Human lyric',
            startTime: const Duration(milliseconds: 500),
            endTime: const Duration(milliseconds: 1500),
          ),
        ],
        timed: true,
        format: 'lrc',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('智能校对提案复核'), findsOneWidget);
    Navigator.of(tester.element(find.text('智能校对提案复核'))).pop(
      LyricProofreadV2Selection(
        acceptedProposalIndices: {0},
        restoredDraftIndices: {},
      ),
    );
    await tester.pumpAndSettle();
    expect(
      editor.document!.lines.single.startTime,
      const Duration(milliseconds: 500),
    );
    expect(editor.alignmentSnapshot, isNotNull);
    expect(editor.undo().applied, isTrue);
    expect(editor.document!.lines.single.startTime, Duration.zero);
    expect(editor.redo().applied, isTrue);
    expect(
      editor.document!.lines.single.startTime,
      const Duration(milliseconds: 500),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editing another row while alignment runs preserves it and allows retry',
    (tester) async {
      final firstRun = Completer<List<ForcedAlignedSpan>>();
      var calls = 0;
      final editor = await _openEditor(tester, ({
        required audioPath,
        required text,
        required language,
        required audioDuration,
      }) {
        calls++;
        return calls == 1 ? firstRun.future : Future.value([]);
      }, initialDocument: _twoLineDocument());
      await _startAlignment(tester);
      expect(calls, 1);
      expect(editor.selectedLineIndex, 0);
      editor.updateLine(
        1,
        editor.document!.lines[1].copyWith(text: 'Second line edited'),
      );
      await tester.pump();
      firstRun.complete([]);
      await tester.pumpAndSettle();
      expect(editor.document!.lines.map((line) => line.text), [
        'Human lyric',
        'Second line edited',
      ]);
      expect(editor.canUndo, isTrue);
      expect(find.textContaining('原提案已丢弃'), findsOneWidget);
      expect(find.text('智能校对提案复核'), findsNothing);
      await _startAlignment(tester);
      expect(calls, 2);
      expect(find.text('智能校对提案复核'), findsOneWidget);
      expect(editor.document!.lines[1].text, 'Second line edited');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an edit to another row invalidates a real reference proposal', (
    tester,
  ) async {
    final editor = await _openEditor(
      tester,
      _emptyAlignment,
      initialDocument: _twoLineDocument(),
    );
    await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('智能校对 V2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('参考歌词优先'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(ReferenceAlignmentDialog))).pop(
      ReferenceLyricInput(
        lines: [
          ReferenceLyricLine(
            text: 'Human lyric',
            startTime: const Duration(milliseconds: 500),
            endTime: const Duration(milliseconds: 1500),
          ),
          ReferenceLyricLine(
            text: 'Second line',
            startTime: const Duration(milliseconds: 2100),
            endTime: const Duration(milliseconds: 2900),
          ),
        ],
        timed: true,
        format: 'lrc',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('智能校对提案复核'), findsOneWidget);
    editor.updateLine(
      1,
      editor.document!.lines[1].copyWith(text: 'My second line'),
    );
    await tester.pump();
    Navigator.of(tester.element(find.text('智能校对提案复核'))).pop(
      LyricProofreadV2Selection(
        acceptedProposalIndices: {0, 1},
        restoredDraftIndices: {},
      ),
    );
    await tester.pumpAndSettle();
    expect(editor.document!.lines[0].startTime, Duration.zero);
    expect(editor.document!.lines[1].text, 'My second line');
    expect(editor.alignmentSnapshot, isNull);
    expect(editor.undo().applied, isTrue);
    expect(editor.document!.lines[1].text, 'Second line');
    expect(editor.redo().applied, isTrue);
    expect(editor.document!.lines[1].text, 'My second line');
    expect(find.textContaining('原提案已丢弃'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reloading while alignment runs discards the old song result', (
    tester,
  ) async {
    final pending = Completer<List<ForcedAlignedSpan>>();
    final editor = await _openEditor(
      tester,
      ({
        required audioPath,
        required text,
        required language,
        required audioDuration,
      }) => pending.future,
      initialDocument: _twoLineDocument(),
    );
    await _startAlignment(tester);
    editor.load(_document('Reloaded lyric'));
    await tester.pump();
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(editor.document!.lines.single.text, 'Reloaded lyric');
    expect(editor.canUndo, isFalse);
    expect(find.text('智能校对提案复核'), findsNothing);
    expect(find.textContaining('原提案已丢弃'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'untimed secondary input reports an error without modifying lyrics',
    (tester) async {
      var calls = 0;
      final editor = await _openEditor(tester, ({
        required audioPath,
        required text,
        required language,
        required audioDuration,
      }) async {
        calls++;
        return [];
      });
      await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('智能校对 V2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ASR 优先'));
      await tester.pumpAndSettle();
      final field = find.byKey(
        const ValueKey('secondary_asr_transcript_input'),
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, 'no timestamps here');
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(find.textContaining('必须为每行都带时间戳'), findsOneWidget);
      expect(editor.document!.lines.single.text, 'Human lyric');
      expect(editor.hasChanges, isFalse);
      expect(calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('busy alignment explains retry and never changes lyrics', (
    tester,
  ) async {
    final repository = MemoryProjectRepository();
    var project = await repository.createProject(name: 'Song');
    project = await repository.updateProject(
      project.copyWith(
        lyricDocument: _document('Human lyric'),
        audioAsset: const AudioAsset(
          originalPath: 'song.wav',
          format: 'wav',
          duration: Duration(seconds: 3),
        ),
      ),
    );
    var calls = 0;
    final dependencies = LyricEditorDependencies(
      projectRepository: repository,
      playbackSession: _FakePlaybackSession(),
      audioPlayer: _FakeAudioPlayer(),
      lyricFileExport: _FakeLyricFileExport(),
      lyricFileImport: _FakeLyricFileImport(),
      forcedAlignmentRunner:
          ({
            required audioPath,
            required text,
            required language,
            required audioDuration,
          }) async {
            calls++;
            throw const ForcedAlignmentResourceBusyException();
          },
    );
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: LyricEditorScreen(
          projectId: project.id,
          dependencies: dependencies,
        ),
      ),
    );
    await _settleAndAssertNoFrameworkException(tester, 'initial render');
    await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('智能校对 V2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ASR 优先'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('forced_alignment_review_toggle')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('识别资源正忙，请等待其他任务结束后重试'), findsOneWidget);
    expect(find.text('智能校对提案复核'), findsNothing);
    expect(
      (await repository.getProjectById(
        project.id,
      ))!.lyricDocument!.lines.single.text,
      'Human lyric',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'stale editor save is rejected, edits remain, and explicit overwrite preserves new metadata',
    (tester) async {
      final repository = MemoryProjectRepository();
      var project = await repository.createProject(name: 'Song');
      project = await repository.updateProject(
        project.copyWith(lyricDocument: _document('Original lyric')),
      );
      final dependencies = LyricEditorDependencies(
        projectRepository: repository,
        playbackSession: _FakePlaybackSession(),
        audioPlayer: _FakeAudioPlayer(),
        lyricFileExport: _FakeLyricFileExport(),
        lyricFileImport: _FakeLyricFileImport(),
        forcedAlignmentRunner: _emptyAlignment,
      );

      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: LyricEditorScreen(
            projectId: project.id,
            dependencies: dependencies,
          ),
        ),
      );
      await _settleAndAssertNoFrameworkException(tester, 'initial render');
      final lyricField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '歌词文本',
      );
      if (lyricField.evaluate().isEmpty) {
        // If the editor has no default selection, choose the row explicitly.
        // The same text may also be rendered in the inspector once selected.
        await tester.tap(find.text('Original lyric').first);
        await _settleAndAssertNoFrameworkException(tester, 'select lyric');
      }
      expect(lyricField, findsOneWidget);
      tester.widget<TextField>(lyricField).onChanged?.call('Local edit');
      await _settleAndAssertNoFrameworkException(tester, 'edit lyric');
      expect(find.byIcon(Icons.save_rounded), findsOneWidget);

      final backgroundUpdate = await repository.updateProject(
        project.copyWith(
          lyricDocument: _document('Background transcription'),
          currentStage: ProcessingStage.transcriptionComplete,
          metadata: const {
            'transcription': {'engine': 'qwen'},
          },
        ),
      );

      final saveButton = find.byIcon(Icons.save_rounded);
      expect(saveButton, findsOneWidget);
      await tester.tap(saveButton);
      await _settleAndAssertNoFrameworkException(tester, 'reject stale save');
      expect(find.text('工程已在其他位置更新'), findsOneWidget);
      expect(find.textContaining('你的编辑仍保留'), findsOneWidget);

      final afterRejectedSave = await repository.getProjectById(project.id);
      expect(
        afterRejectedSave?.lyricDocument?.lines.single.text,
        'Background transcription',
      );
      expect(afterRejectedSave?.metadata['transcription'], {'engine': 'qwen'});

      await tester.tap(find.text('继续编辑'));
      await _settleAndAssertNoFrameworkException(tester, 'continue editing');
      expect(
        tester.widget<TextField>(lyricField).controller?.text,
        'Local edit',
      );

      await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
      await _settleAndAssertNoFrameworkException(tester, 'retry save');
      await tester.tap(find.text('用当前歌词覆盖最新版'));
      await _settleAndAssertNoFrameworkException(tester, 'confirm overwrite');

      final explicitlyOverwritten = await repository.getProjectById(project.id);
      expect(
        explicitlyOverwritten?.lyricDocument?.lines.single.text,
        'Local edit',
      );
      expect(explicitlyOverwritten?.metadata['transcription'], {
        'engine': 'qwen',
      });
      expect(explicitlyOverwritten?.revision, backgroundUpdate.revision + 1);
    },
  );
}

Future<void> _openReferenceEvidenceReview(
  WidgetTester tester,
  String reference,
) async {
  await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('智能校对 V2'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('参考歌词优先'));
  await tester.pumpAndSettle();
  final toggle = find.byKey(const ValueKey('forced_alignment_review_toggle'));
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.tap(find.text('继续'));
  await tester.pumpAndSettle();
  expect(find.byType(ReferenceAlignmentDialog), findsOneWidget);
  _submitReference(tester, reference);
  await tester.pumpAndSettle();
  expect(find.text('智能校对提案复核'), findsOneWidget);
}

Future<void> _selectProjectEvidence(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('智能校对 V2'));
  await tester.pumpAndSettle();
  final toggle = find.byKey(const ValueKey('project_asr_evidence_toggle'));
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await tester.tap(find.text('继续'));
  await tester.pumpAndSettle();
}

Future<void> _openReferenceFlow(WidgetTester tester, String action) async {
  await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
  expect(find.byType(ReferenceAlignmentDialog), findsOneWidget);
}

void _submitReference(WidgetTester tester, String text) {
  Navigator.of(tester.element(find.byType(ReferenceAlignmentDialog))).pop(
    ReferenceLyricInput(
      lines: [ReferenceLyricLine(text: text)],
      timed: false,
      format: 'plain',
    ),
  );
}

Future<LyricEditorDocumentController> _openEditor(
  WidgetTester tester,
  ForcedAlignmentRunner runner, {
  LyricDocument? initialDocument,
  String? vocalPath,
  ProjectProofreadEvidenceLoader? evidenceLoader,
  ReferenceAlignmentAudioGuard? timingGuard,
  AudioPlayerService? previewAudio,
  _PreviewPlaybackSession? previewSession,
}) async {
  final repository = MemoryProjectRepository();
  var project = await repository.createProject(name: 'Song');
  project = await repository.updateProject(
    project.copyWith(
      lyricDocument: initialDocument ?? _document('Human lyric'),
      audioAsset: AudioAsset(
        originalPath: 'song.wav',
        vocalPath: vocalPath,
        format: 'wav',
        duration: Duration(seconds: 3),
      ),
    ),
  );
  previewSession?.setProject(project);
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: LyricEditorScreen(
        projectId: project.id,
        dependencies: LyricEditorDependencies(
          projectRepository: repository,
          playbackSession: previewSession ?? _FakePlaybackSession(),
          audioPlayer: previewAudio ?? _FakeAudioPlayer(),
          lyricFileExport: _FakeLyricFileExport(),
          lyricFileImport: LocalLyricFileImportService(),
          forcedAlignmentRunner: runner,
          projectProofreadEvidenceLoader: evidenceLoader,
          referenceAlignmentAudioGuard: timingGuard,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final field = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == '歌词文本',
  );
  return Provider.of<LyricEditorDocumentController>(
    tester.element(field),
    listen: false,
  );
}

Future<void> _startAlignment(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('智能校对 V2'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('ASR 优先'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('forced_alignment_review_toggle')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('继续'));
  await tester.pumpAndSettle();
}

Future<void> _settleAndAssertNoFrameworkException(
  WidgetTester tester,
  String operation,
) async {
  await tester.pumpAndSettle();
  final exception = tester.takeException();
  if (exception != null) {
    fail('Unhandled Flutter exception after $operation: $exception');
  }
}

LyricDocument _document(String text) => LyricDocument(
  language: 'en',
  lines: [
    LyricLine(
      text: text,
      startTime: Duration.zero,
      endTime: const Duration(seconds: 2),
    ),
  ],
);

LyricDocument _twoLineDocument() => LyricDocument(
  language: 'en',
  lines: [
    ..._document('Human lyric').lines,
    const LyricLine(
      text: 'Second line',
      startTime: Duration(milliseconds: 2100),
      endTime: Duration(milliseconds: 2900),
    ),
  ],
);

Future<List<ForcedAlignedSpan>> _emptyAlignment({
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

class _FakeLyricFileImport implements LyricFileImportService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReferenceTimingGuard implements ReferenceAlignmentAudioGuard {
  int verifyCalls = 0;
  int? failVerifyAt;
  ReferenceAlignmentAudioStatus captureStatus =
      ReferenceAlignmentAudioStatus.matches;

  @override
  Future<ReferenceAlignmentAudioCheck> capture({
    required String projectId,
    required int projectRevision,
    required String audioPath,
  }) async {
    return ReferenceAlignmentAudioCheck(
      status: captureStatus,
      snapshot: captureStatus == ReferenceAlignmentAudioStatus.matches
          ? ReferenceAlignmentAudioSnapshot(
              projectId: projectId,
              projectRevision: projectRevision,
              audioPath: audioPath,
              audioSha256: 'test',
            )
          : null,
    );
  }

  @override
  Future<ReferenceAlignmentAudioCheck> verify(
    ReferenceAlignmentAudioSnapshot snapshot,
  ) async {
    verifyCalls++;
    if (verifyCalls == failVerifyAt)
      return const ReferenceAlignmentAudioCheck(
        status: ReferenceAlignmentAudioStatus.audioChanged,
      );
    return ReferenceAlignmentAudioCheck(
      status: ReferenceAlignmentAudioStatus.matches,
      snapshot: snapshot,
    );
  }
}

class _PreviewAudioPlayer extends _FakeAudioPlayer {
  PlaybackState state;
  int playCalls = 0;
  int pauseCalls = 0;
  Completer<void>? playGate;
  _PreviewAudioPlayer({required AudioSourceType source})
    : state = const PlaybackState.idle().copyWith(
        currentSource: source,
        duration: const Duration(seconds: 3),
      );
  @override
  PlaybackState get currentState => state;
  @override
  Future<void> play() async {
    playCalls++;
    if (playGate != null) await playGate!.future;
    state = state.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    state = state.copyWith(isPlaying: false);
  }
}

class _PreviewPlaybackSession extends _FakePlaybackSession {
  PlaybackSessionState state = const PlaybackSessionState();
  final List<Duration> seeks = [];
  Completer<void>? seekGate;
  int playItemCalls = 0;
  void setProject(ProjectManifest project) {
    state = PlaybackSessionState(
      queue: [
        PlaybackItem(
          id: project.id,
          title: project.name,
          projectId: project.id,
          audioAsset: project.audioAsset!,
        ),
      ],
      currentIndex: 0,
    );
  }

  @override
  PlaybackSessionState get currentState => state;
  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    if (seekGate != null) await seekGate!.future;
  }

  @override
  Future<void> playItem(PlaybackItem item, {Duration? resumeFrom}) async {
    playItemCalls++;
  }
}
