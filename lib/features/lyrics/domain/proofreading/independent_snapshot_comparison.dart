import '../../../project/domain/models/lyric_document.dart';

/// A relationship between original engine segments, never between a snapshot
/// and the current editable document.
enum SnapshotComparisonKind {
  exactText,
  differentText,
  primaryOnly,
  secondaryOnly,
  ambiguousOverlap,
}

class SnapshotComparisonRow {
  final SnapshotComparisonKind kind;
  final int? primaryIndex;
  final int? secondaryIndex;
  final LyricLine? primary;
  final LyricLine? secondary;

  const SnapshotComparisonRow({
    required this.kind,
    this.primaryIndex,
    this.secondaryIndex,
    this.primary,
    this.secondary,
  });
}

class SnapshotComparison {
  /// Whether the safety budget prevented building any comparison rows.
  final bool limitExceeded;
  final List<SnapshotComparisonRow> rows;

  SnapshotComparison._({
    required this.limitExceeded,
    required List<SnapshotComparisonRow> rows,
  }) : rows = List.unmodifiable(rows);
}

/// Strict one-to-one interval matching for read-only inspection.
///
/// Overlapping segments can be split, merged or duplicated. Such relationships
/// are explicitly ambiguous and never count as independent agreement. Exact
/// text equality means only that two raw strings match, not that they are true.
/// No padding, offset, fuzzy text comparison, or draft mapping is performed.
class IndependentSnapshotComparison {
  static const maxLinesPerTranscript = 400;
  static const maxTextRunesPerLine = 4096;

  const IndependentSnapshotComparison();

  SnapshotComparison compare({
    required LyricDocument primary,
    required LyricDocument secondary,
  }) {
    if (!_withinBudget(primary) || !_withinBudget(secondary)) {
      return SnapshotComparison._(limitExceeded: true, rows: const []);
    }
    // Each source index remains attached to its own transcript. This is not
    // a mapping into the user's current document.
    final byPrimary = List.generate(primary.lines.length, (_) => <int>[]);
    final bySecondary = List.generate(secondary.lines.length, (_) => <int>[]);
    for (var pi = 0; pi < primary.lines.length; pi++) {
      for (var si = 0; si < secondary.lines.length; si++) {
        if (_overlaps(primary.lines[pi], secondary.lines[si])) {
          byPrimary[pi].add(si);
          bySecondary[si].add(pi);
        }
      }
    }
    final rows = <SnapshotComparisonRow>[];
    for (var pi = 0; pi < primary.lines.length; pi++) {
      final line = primary.lines[pi];
      final matches = byPrimary[pi];
      if (matches.isEmpty) {
        rows.add(
          SnapshotComparisonRow(
            kind: SnapshotComparisonKind.primaryOnly,
            primaryIndex: pi,
            primary: line,
          ),
        );
      } else if (matches.length != 1 ||
          bySecondary[matches.single].length != 1) {
        rows.add(
          SnapshotComparisonRow(
            kind: SnapshotComparisonKind.ambiguousOverlap,
            primaryIndex: pi,
            primary: line,
          ),
        );
      } else {
        final si = matches.single;
        final other = secondary.lines[si];
        rows.add(
          SnapshotComparisonRow(
            kind: line.text == other.text
                ? SnapshotComparisonKind.exactText
                : SnapshotComparisonKind.differentText,
            primaryIndex: pi,
            secondaryIndex: si,
            primary: line,
            secondary: other,
          ),
        );
      }
    }
    for (var si = 0; si < secondary.lines.length; si++) {
      final matches = bySecondary[si];
      if (matches.isEmpty ||
          matches.length != 1 ||
          byPrimary[matches.single].length != 1) {
        rows.add(
          SnapshotComparisonRow(
            kind: matches.isEmpty
                ? SnapshotComparisonKind.secondaryOnly
                : SnapshotComparisonKind.ambiguousOverlap,
            secondaryIndex: si,
            secondary: secondary.lines[si],
          ),
        );
      }
    }
    return SnapshotComparison._(limitExceeded: false, rows: rows);
  }

  bool _withinBudget(LyricDocument document) {
    if (document.lines.length > maxLinesPerTranscript ||
        (document.globalOffset ?? Duration.zero) != Duration.zero) {
      return false;
    }
    for (final line in document.lines) {
      if (line.startTime.isNegative ||
          line.endTime <= line.startTime ||
          line.text.trim().isEmpty ||
          line.text.runes.length > maxTextRunesPerLine) {
        return false;
      }
    }
    return true;
  }

  bool _overlaps(LyricLine a, LyricLine b) =>
      a.startTime < b.endTime && b.startTime < a.endTime;
}
