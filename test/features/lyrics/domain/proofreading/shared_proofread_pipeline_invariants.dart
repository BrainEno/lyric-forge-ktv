import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

const _minimumOrdinaryLineDuration = Duration(milliseconds: 300);

String snapshotLyricDocument(LyricDocument document) =>
    jsonEncode(document.toJson());

/// Shared invariant checks used by both proofreading pipelines.
///
/// [sourceIndices] maps each proposal row to the input row that supplied it;
/// inserted reference rows use null. Protected input rows must be preserved.
void expectProofreadPipelineInvariants({
  required LyricDocument input,
  required String inputSnapshot,
  required LyricDocument proposedDocument,
  required List<LyricLine> verdictLines,
  required List<String?> lineIds,
  required List<bool> lockedVerdicts,
  required List<int?> sourceIndices,
  Set<int> protectedSourceIndices = const {},
  Duration? audioDuration,
  List<int?>? referenceIndices,
}) {
  final output = proposedDocument.lines;
  expect(
    verdictLines,
    hasLength(output.length),
    reason: 'I7: every output row needs a verdict.',
  );
  expect(
    lineIds,
    hasLength(output.length),
    reason: 'I7: every output row needs a line ID slot.',
  );
  expect(
    lockedVerdicts,
    hasLength(output.length),
    reason: 'Every verdict needs a lock state.',
  );
  expect(
    sourceIndices,
    hasLength(output.length),
    reason: 'Every output row needs source mapping.',
  );
  expect(
    snapshotLyricDocument(input),
    inputSnapshot,
    reason: 'I5: building a proposal must not mutate the source document.',
  );

  final ids = lineIds.whereType<String>().toList();
  expect(
    ids.toSet(),
    hasLength(ids.length),
    reason: 'I7: non-null line IDs must be unique.',
  );

  for (var index = 0; index < output.length; index++) {
    final line = output[index];
    final verdictLine = verdictLines[index];
    final sourceIndex = sourceIndices[index];
    final isProtected =
        sourceIndex != null && protectedSourceIndices.contains(sourceIndex);

    expect(
      _sameLine(line, verdictLine),
      isTrue,
      reason: 'I7: verdict row $index must describe its proposal row.',
    );
    expect(
      lineIds[index],
      line.id,
      reason: 'I7: verdict line ID must match the proposed row.',
    );
    expect(
      line.startTime,
      greaterThanOrEqualTo(Duration.zero),
      reason: 'I6: time cannot be negative.',
    );
    expect(
      line.endTime,
      greaterThan(line.startTime),
      reason: 'Every row needs a positive interval.',
    );
    if (!isProtected) {
      expect(
        line.endTime - line.startTime,
        greaterThanOrEqualTo(_minimumOrdinaryLineDuration),
        reason: 'I2: ordinary output rows must be at least 300 ms.',
      );
    }
    if (audioDuration != null) {
      expect(
        line.endTime,
        lessThanOrEqualTo(audioDuration),
        reason: 'I6: rows cannot exceed audio duration.',
      );
    }

    if (index > 0) {
      final previous = output[index - 1];
      expect(
        line.startTime,
        greaterThanOrEqualTo(previous.startTime),
        reason: 'I1: output start times must be non-decreasing.',
      );
      expect(
        line.startTime,
        greaterThanOrEqualTo(previous.endTime),
        reason: 'I1: adjacent output rows must not overlap.',
      );
      if (referenceIndices != null &&
          _normalizedSimilarity(previous.text, line.text) >= 0.9 &&
          line.startTime < previous.endTime) {
        fail(
          'I3: adjacent duplicate reference rows overlap at indexes '
          '${index - 1} and $index.',
        );
      }
    }

    if (sourceIndex != null) {
      expect(sourceIndex, inInclusiveRange(0, input.lines.length - 1));
    }
    if (isProtected) {
      final protectedIndex = sourceIndex;
      expect(
        lockedVerdicts[index],
        isTrue,
        reason: 'I4: protected rows must be locked.',
      );
      expect(
        _sameLine(line, input.lines[protectedIndex]),
        isTrue,
        reason: 'I4: protected row text, timing, ID and flags must be unchanged.',
      );
    }
  }

  for (final protectedIndex in protectedSourceIndices) {
    expect(protectedIndex, inInclusiveRange(0, input.lines.length - 1));
    expect(
      sourceIndices.where((sourceIndex) => sourceIndex == protectedIndex),
      hasLength(1),
      reason: 'I4: every protected source row must be present exactly once.',
    );
  }

  if (referenceIndices != null) {
    expect(
      referenceIndices,
      hasLength(output.length),
      reason: 'I3: each reference proposal needs an index.',
    );
    for (var index = 0; index < referenceIndices.length; index++) {
      if (referenceIndices[index] == null) {
        final sourceIndex = sourceIndices[index];
        expect(
          sourceIndex != null && protectedSourceIndices.contains(sourceIndex),
          isTrue,
          reason:
              'I3: only an unchanged protected draft row may lack a reference index.',
        );
      }
    }
    final nonNullReferenceIndices = referenceIndices.whereType<int>().toList();
    expect(
      nonNullReferenceIndices.toSet(),
      hasLength(nonNullReferenceIndices.length),
      reason: 'I3: a reference row cannot appear more than once.',
    );
  }
}

bool _sameLine(LyricLine left, LyricLine right) =>
    left.id == right.id &&
    left.text == right.text &&
    left.startTime == right.startTime &&
    left.endTime == right.endTime &&
    left.isChorus == right.isChorus &&
    left.confidence == right.confidence;

double _normalizedSimilarity(String left, String right) {
  final a = _normalize(left).runes.toList();
  final b = _normalize(right).runes.toList();
  if (a.isEmpty || b.isEmpty) {
    return a.isEmpty && b.isEmpty ? 1 : 0;
  }
  final distance = _editDistance(a, b);
  final longest = a.length > b.length ? a.length : b.length;
  return 1 - distance / longest;
}

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), '')
    .replaceAll(RegExp(r'''[.,!?，。！？、;；:：…—\-'"“”‘’（）()【】\[\]{}]'''), '');

int _editDistance(List<int> left, List<int> right) {
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var row = 1; row <= left.length; row++) {
    final current = List<int>.filled(right.length + 1, 0);
    current[0] = row;
    for (var column = 1; column <= right.length; column++) {
      final substitutionCost = left[row - 1] == right[column - 1] ? 0 : 1;
      final deletion = previous[column] + 1;
      final insertion = current[column - 1] + 1;
      final substitution = previous[column - 1] + substitutionCost;
      var best = deletion < insertion ? deletion : insertion;
      if (substitution < best) best = substitution;
      current[column] = best;
    }
    previous = current;
  }
  return previous.last;
}
