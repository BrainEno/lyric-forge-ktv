import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/timing_provenance.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_manual_edit_marker_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_decision_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/lyric_editor_document_controller.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

/// What the editor hands to the repository after a proofread is applied:
/// it must always be writable as JSON and keep the user's confirmations.
void main() {
  LyricLine line(String id, String text, int startMs) => LyricLine(
    id: id,
    text: text,
    startTime: Duration(milliseconds: startMs),
    endTime: Duration(milliseconds: startMs + 1500),
  );

  LyricEditorDocumentController loaded(LyricDocument document) {
    final controller = LyricEditorDocumentController(
      clock: () => DateTime.utc(2026, 11, 28),
    );
    controller.load(document);
    return controller;
  }

  test('an applied proofread with odd metadata still encodes', () {
    final controller = loaded(
      LyricDocument(language: 'zh', lines: [line('a', '原稿', 0)]),
    );
    final proofread = LyricDocument(
      language: 'zh',
      lines: [line('a', '校对后', 0)],
      metadata: {
        'timingProvenance': {
          'a': LyricTimingProvenance.forcedAlignmentReference,
        },
        'referenceLineIds': <String>{'a'},
        'similarity': double.nan,
      },
    );

    controller.replaceDocument(
      proofread,
      label: '应用校对提案',
      selectedLineIndex: 0,
      keepBatchSnapshot: true,
      isReferenceProofread: true,
    );
    final saved = controller.documentForSave();

    expect(() => jsonEncode(saved.toJson()), returnsNormally);
    expect(saved.lines.single.text, '校对后');
    expect(saved.metadata['timingProvenance'], {
      'a': 'forcedAlignmentReference',
    });
    expect(saved.metadata['referenceLineIds'], ['a']);
    expect(saved.metadata.containsKey('similarity'), isFalse);
  });

  test('confirmed lines and manual marks survive the JSON round trip', () {
    final controller = loaded(
      LyricDocument(
        language: 'zh',
        lines: [line('a', '第一行', 0), line('b', '第二行', 1500)],
      ),
    );
    controller.setLineReviewed(1, reviewed: true);

    final saved = controller.documentForSave();
    final decoded = LyricDocument.fromJson(
      jsonDecode(jsonEncode(saved.toJson())) as Map<String, dynamic>,
    );

    const decisions = LyricReviewDecisionService();
    expect(decisions.reviewedIndices(decoded), {1});
    expect(
      decoded.metadata[LyricManualEditMarkerService.manuallyEditedLineIdsKey],
      isA<List<dynamic>>(),
    );
  });

  test('plain metadata passes through untouched', () {
    final controller = loaded(
      const LyricDocument(
        language: 'zh',
        lines: [],
        metadata: {'source': 'reference-alignment', 'lineCount': 2},
      ),
    );

    final saved = controller.documentForSave();

    expect(saved.metadata['source'], 'reference-alignment');
    expect(saved.metadata['lineCount'], 2);
    expect(
      saved.metadata[LyricManualEditMarkerService.manuallyEditedLineIdsKey],
      isEmpty,
    );
  });
}
