import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

class ProofreadInvariantRow {
  const ProofreadInvariantRow({
    required this.line,
    required this.lineId,
    required this.isLocked,
    this.sourceIndex,
    this.referenceIndex,
    this.timingConflict = false,
  });

  final LyricLine line;
  final String? lineId;
  final bool isLocked;
  final int? sourceIndex;
  final int? referenceIndex;

  /// ASR-first preserves invalid source timestamps for review rather than
  /// silently changing them. Such rows must carry an explicit timing conflict.
  final bool timingConflict;
}

String snapshotDocument(LyricDocument document) =>
    jsonEncode(document.toJson());

/// Shared contract checks used by reference-first and ASR-first pipeline tests.
void expectInvariants({
  required LyricDocument source,
  required String sourceSnapshot,
  required LyricDocument proposedDocument,
  required List<ProofreadInvariantRow> rows,
  Set<int> protectedSourceIndices = const <int>{},
  Duration? audioDuration,
  bool requireUniqueReferenceIndices = false,
}) {
  final output = proposedDocument.lines;
  expect(
    rows,
    hasLength(output.length),
    reason: 'Every output needs one verdict row.',
  );

  for (var index = 0; index < output.length; index++) {
    final row = rows[index];
    final line = output[index];
    expect(
      _sameLine(row.line, line),
      isTrue,
      reason: 'Verdict row $index must describe the corresponding output line.',
    );
    expect(
      row.lineId,
      line.id,
      reason: 'Verdict lineId must match the output ID.',
    );

    if (index > 0 &&
        !rows[index - 1].timingConflict &&
        !row.timingConflict) {
      final previous = output[index - 1];
      expect(
        line.startTime,
        greaterThanOrEqualTo(previous.startTime),
        reason: 'I1: output start times must be non-decreasing.',
      );
      expect(
        line.startTime,
        greaterThanOrEqualTo(previous.endTime),
        reason: 'I1: adjacent output lines must not overlap.',
      );
    }

    final hasInvalidInterval =
        line.startTime.isNegative ||
        line.endTime <= line.startTime ||
        (audioDuration != null && line.endTime > audioDuration);
    if (hasInvalidInterval) {
      expect(
        row.timingConflict,
        isTrue,
        reason: 'I6: an invalid source interval must be explicitly marked for review.',
      );
    }
    if (!row.timingConflict) {
      expect(
        line.startTime,
        greaterThanOrEqualTo(Duration.zero),
        reason: 'I6: accepted output cannot start before zero.',
      );
      expect(
        line.endTime,
        greaterThan(line.startTime),
        reason: 'I6: accepted output must have a positive interval.',
      );
      if (audioDuration != null) {
        expect(
          line.endTime,
          lessThanOrEqualTo(audioDuration),
          reason: 'I6: accepted output cannot exceed the known audio duration.',
        );
      }
    }

    if (!row.isLocked && !row.timingConflict) {
      expect(
        line.endTime - line.startTime,
        greaterThanOrEqualTo(const Duration(milliseconds: 300)),
        reason: 'I2: ordinary output lines must last at least 300 ms.',
      );
    }

    if (row.sourceIndex != null &&
        protectedSourceIndices.contains(row.sourceIndex)) {
      expect(
        row.isLocked,
        isTrue,
        reason: 'I4: protected source rows must stay locked.',
      );
      expect(
        _sameLine(line, source.lines[row.sourceIndex!]),
        isTrue,
        reason: 'I4: protected text, timing, ID, and attributes must be preserved.',
      );
    }

    if (index > 0 &&
        !rows[index - 1].timingConflict &&
        !row.timingConflict &&
        _intervalsOverlap(output[index - 1], line) &&
        _similarity(output[index - 1].text, line.text) >= 0.9) {
      expect(
        false,
        isTrue,
        reason: 'I3: highly similar adjacent lyric rows must not overlap.',
      );
    }
  }

  final ids = output.map((line) => line.id).whereType<String>().toList();
  expect(
    ids.toSet(),
    hasLength(ids.length),
    reason: 'I7: non-null line IDs must be unique.',
  );

  if (requireUniqueReferenceIndices) {
    final referenceIndices = rows
        .map((row) => row.referenceIndex)
        .whereType<int>()
        .toList();
    expect(
      referenceIndices.toSet(),
      hasLength(referenceIndices.length),
      reason: 'I3: a reference line may appear at most once.',
    );
  }

  for (final protectedIndex in protectedSourceIndices) {
    expect(
      protectedIndex >= 0 && protectedIndex < source.lines.length,
      isTrue,
      reason: 'Protected source index must be valid.',
    );
    if (protectedIndex < 0 || protectedIndex >= source.lines.length) continue;
    final preservedRows = rows
        .where((row) => row.sourceIndex == protectedIndex)
        .toList();
    expect(
      preservedRows,
      hasLength(1),
      reason: 'Every protected source row must occur exactly once in the proposal.',
    );
    if (preservedRows.length == 1) {
      expect(preservedRows.single.isLocked, isTrue);
      expect(
        _sameLine(preservedRows.single.line, source.lines[protectedIndex]),
        isTrue,
      );
    }
  }

  expect(
    snapshotDocument(source),
    sourceSnapshot,
    reason: 'I5: generating a proposal must not mutate the input document.',
  );
}

bool _sameLine(LyricLine left, LyricLine right) =>
    left.id == right.id &&
    left.text == right.text &&
    left.startTime == right.startTime &&
    left.endTime == right.endTime &&
    left.isChorus == right.isChorus &&
    left.confidence == right.confidence;

bool _intervalsOverlap(LyricLine left, LyricLine right) =>
    left.startTime < right.endTime && right.startTime < left.endTime;

double _similarity(String left, String right) {
  final leftRunes = _normalize(left).runes.toList();
  final rightRunes = _normalize(right).runes.toList();
  final longest = math.max(leftRunes.length, rightRunes.length);
  if (longest == 0) return 1;
  if (leftRunes.isEmpty || rightRunes.isEmpty) return 0;

  var previous = List<int>.generate(rightRunes.length + 1, (index) => index);
  for (var i = 1; i <= leftRunes.length; i++) {
    final current = List<int>.filled(rightRunes.length + 1, 0);
    current[0] = i;
    for (var j = 1; j <= rightRunes.length; j++) {
      final substitutionCost =
          leftRunes[i - 1] == rightRunes[j - 1] ? 0 : 1;
      current[j] = math.min(
        math.min(previous[j] + 1, current[j - 1] + 1),
        previous[j - 1] + substitutionCost,
      );
    }
    previous = current;
  }
  return 1 - previous[rightRunes.length] / longest;
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
