import '../../../project/domain/models/lyric_document.dart';
import '../models/secondary_only_suggestion.dart';
import 'lyric_indexed_review_metadata.dart';
import 'lyric_line_structure_service.dart';
import 'lyric_manual_edit_marker_service.dart';
import 'lyric_text_cleanup_service.dart';

/// What a structure suggestion would do.
enum LyricStructureSuggestionKind {
  /// One row holds more than fits a karaoke line; split it at a break.
  splitLongLine,

  /// A row is a fragment cut off its neighbour by a recogniser pause; merge
  /// the two rows.
  mergeFragment,
}

/// One proposed split or merge, ready to preview.
class LyricStructureSuggestion {
  final LyricStructureSuggestionKind kind;

  /// Row the suggestion starts at. For a merge this is the earlier row; the
  /// later one is `index + 1`.
  final int index;

  /// Text of the affected rows before the change (one row for a split, two
  /// for a merge).
  final List<String> before;

  /// Text of the rows after the change (two rows for a split, one for a
  /// merge).
  final List<String> after;

  /// False when the split falls between two characters because the line has
  /// no whitespace or punctuation break. Such suggestions start unselected:
  /// only the user can tell where a sung line ends.
  final bool confident;

  /// The boundary time of a split; null for merges.
  final Duration? splitTime;

  const LyricStructureSuggestion({
    required this.kind,
    required this.index,
    required this.before,
    required this.after,
    required this.confident,
    this.splitTime,
    this.textOffset,
  });

  /// Code-unit offset where a split's second half begins; null for merges.
  final int? textOffset;

  /// Rows this suggestion touches.
  List<int> get affectedIndices =>
      kind == LyricStructureSuggestionKind.splitLongLine
      ? [index]
      : [index, index + 1];
}

/// Every structure suggestion for a document, plus how to apply a selection.
class LyricStructurePlan {
  final List<LyricStructureSuggestion> suggestions;

  /// Rows that would have been suggested but were edited by hand.
  final Set<int> skippedProtectedIndices;

  const LyricStructurePlan({
    required this.suggestions,
    required this.skippedProtectedIndices,
  });

  static const LyricStructurePlan empty = LyricStructurePlan(
    suggestions: [],
    skippedProtectedIndices: {},
  );

  bool get isEmpty => suggestions.isEmpty;

  int get splitCount => suggestions
      .where((s) => s.kind == LyricStructureSuggestionKind.splitLongLine)
      .length;

  int get mergeCount => suggestions
      .where((s) => s.kind == LyricStructureSuggestionKind.mergeFragment)
      .length;

  /// [document] with the suggestions at [selected] (positions in
  /// [suggestions]) applied in one pass.
  ///
  /// Row-indexed engine evidence follows the rows that did not change and is
  /// dropped for rows that were split or merged. New rows get fresh ids.
  LyricDocument applyTo(
    LyricDocument document,
    Set<int> selected, {
    LyricLineStructureService structure = const LyricLineStructureService(),
    LyricManualEditMarkerService markers = const LyricManualEditMarkerService(),
  }) {
    final splits = <int, LyricLineSplit>{};
    final merges = <int>{};
    for (final position in selected) {
      if (position < 0 || position >= suggestions.length) continue;
      final suggestion = suggestions[position];
      final index = suggestion.index;
      switch (suggestion.kind) {
        case LyricStructureSuggestionKind.splitLongLine:
          if (index >= document.lines.length) continue;
          final result = structure.split(
            document.lines[index],
            textOffset: suggestion.textOffset,
          );
          final split = result.split;
          if (split != null) splits[index] = split;
        case LyricStructureSuggestionKind.mergeFragment:
          if (index + 1 < document.lines.length) merges.add(index);
      }
    }
    if (splits.isEmpty && merges.isEmpty) return document;

    final lines = <LyricLine>[];
    final newIndexOf = <int, int?>{};
    for (var index = 0; index < document.lines.length; index++) {
      final line = document.lines[index];
      final split = splits[index];
      if (split != null) {
        newIndexOf[index] = null;
        lines
          ..add(split.first)
          ..add(split.second);
      } else if (merges.contains(index)) {
        newIndexOf[index] = null;
        newIndexOf[index + 1] = null;
        lines.add(structure.merge(line, document.lines[index + 1]));
        index++;
      } else {
        newIndexOf[index] = lines.length;
        lines.add(line);
      }
    }

    return markers.assignMissingLineIds(
      document.copyWith(
        lines: lines,
        metadata: LyricIndexedReviewMetadata.remapped(
          document.metadata,
          (index) => newIndexOf[index],
        ),
      ),
    );
  }

  /// Row to select after applying: the first changed row. Rows before it are
  /// untouched, so its index does not move.
  int? selectionAfterApply(Set<int> selected) {
    final chosen = [
      for (final position in selected)
        if (position >= 0 && position < suggestions.length)
          suggestions[position],
    ]..sort((a, b) => a.index.compareTo(b.index));
    return chosen.isEmpty ? null : chosen.first.index;
  }
}

/// Finds rows whose segmentation does not fit a karaoke display: rows too
/// long to sing as one line and fragments a recogniser pause cut off.
///
/// It only proposes; [LyricStructurePlan.applyTo] changes nothing the user
/// did not select. Rows edited by hand, empty rows, "建议补入" rows (which
/// need a keep-or-delete decision first) and caption or [音乐] rows (which the
/// clean-up tool deletes rather than merges into a lyric) are never touched.
class LyricStructureAdvisor {
  const LyricStructureAdvisor({
    this.structure = const LyricLineStructureService(),
    this.cleanup = const LyricTextCleanupService(),
    this.maximumLineWeight = 20,
    this.fragmentMaximumWeight = 2,
    this.fragmentMaximumDuration = const Duration(milliseconds: 700),
    this.mergeMaximumGap = const Duration(milliseconds: 350),
  });

  final LyricLineStructureService structure;
  final LyricTextCleanupService cleanup;

  /// Sung weight (Han-character units) above which a row is too long for one
  /// karaoke line. Latin letters count half, so this is about 40 letters.
  final double maximumLineWeight;

  /// A row at or below this sung weight is a fragment candidate.
  final double fragmentMaximumWeight;

  /// A row shorter than this is a fragment candidate whatever its text.
  final Duration fragmentMaximumDuration;

  /// Largest silence between a fragment and the neighbour it merges into.
  final Duration mergeMaximumGap;

  LyricStructurePlan analyze(
    LyricDocument document, {
    Set<int> protectedIndices = const {},
  }) {
    final lines = document.lines;
    if (lines.isEmpty) return LyricStructurePlan.empty;
    final suggestionRows = SecondaryOnlySuggestion.resolve(document).keys;
    final excluded = {...suggestionRows};
    final skippedProtected = <int>{};
    final used = <int>{};
    final suggestions = <LyricStructureSuggestion>[];

    bool eligible(int index) {
      if (index < 0 || index >= lines.length) return false;
      if (excluded.contains(index) || used.contains(index)) return false;
      final text = lines[index].text.trim();
      if (text.isEmpty) return false;
      return !cleanup.isAsrBoilerplate(text) && !cleanup.isAnnotationOnly(text);
    }

    for (var index = 0; index < lines.length; index++) {
      if (!eligible(index)) continue;
      final line = lines[index];
      final weight = structure.sungWeight(line.text);

      if (weight > maximumLineWeight) {
        if (protectedIndices.contains(index)) {
          skippedProtected.add(index);
          continue;
        }
        final result = structure.split(line);
        final split = result.split;
        if (split == null) continue;
        used.add(index);
        suggestions.add(
          LyricStructureSuggestion(
            kind: LyricStructureSuggestionKind.splitLongLine,
            index: index,
            before: [line.text],
            after: [split.first.text, split.second.text],
            confident: structure.hasNaturalBreak(line.text),
            splitTime: split.splitTime,
            textOffset: split.textOffset,
          ),
        );
        continue;
      }

      final duration = line.endTime - line.startTime;
      final isFragment =
          weight <= fragmentMaximumWeight ||
          duration < fragmentMaximumDuration;
      if (!isFragment) continue;

      final partner = _mergePartner(lines, index, weight, eligible);
      if (partner == null) continue;
      final first = partner < index ? partner : index;
      if (protectedIndices.contains(first) ||
          protectedIndices.contains(first + 1)) {
        skippedProtected.addAll({first, first + 1});
        continue;
      }
      used.addAll({first, first + 1});
      suggestions.add(
        LyricStructureSuggestion(
          kind: LyricStructureSuggestionKind.mergeFragment,
          index: first,
          before: [lines[first].text, lines[first + 1].text],
          after: [structure.merge(lines[first], lines[first + 1]).text],
          confident: true,
        ),
      );
    }

    suggestions.sort((a, b) => a.index.compareTo(b.index));
    return LyricStructurePlan(
      suggestions: List.unmodifiable(suggestions),
      skippedProtectedIndices: Set.unmodifiable(skippedProtected),
    );
  }

  /// The neighbour to merge a fragment into: the closer one in time, as long
  /// as the silence between them is short and the result still fits a line.
  int? _mergePartner(
    List<LyricLine> lines,
    int index,
    double weight,
    bool Function(int) eligible,
  ) {
    final line = lines[index];
    int? best;
    Duration? bestGap;
    for (final neighbour in [index - 1, index + 1]) {
      if (!eligible(neighbour)) continue;
      final other = lines[neighbour];
      final gap = neighbour < index
          ? line.startTime - other.endTime
          : other.startTime - line.endTime;
      if (gap.isNegative || gap > mergeMaximumGap) continue;
      if (weight + structure.sungWeight(other.text) > maximumLineWeight) {
        continue;
      }
      if (bestGap == null || gap < bestGap) {
        best = neighbour;
        bestGap = gap;
      }
    }
    return best;
  }
}
