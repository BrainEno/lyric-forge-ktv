import 'dart:math' as math;

import 'lyric_tokenizer.dart';
import 'proofread_constants.dart';

class TokenMatch {
  final int referenceIndex;
  final int draftIndex;
  final double similarity;

  const TokenMatch({
    required this.referenceIndex,
    required this.draftIndex,
    required this.similarity,
  });
}

class ReferenceTokenAlignmentResult {
  final List<String> referenceTokens;
  final List<String> draftTokens;
  final List<TokenMatch> matches;
  final bool dpBudgetExceeded;

  ReferenceTokenAlignmentResult({
    required List<String> referenceTokens,
    required List<String> draftTokens,
    required List<TokenMatch> matches,
    required this.dpBudgetExceeded,
  }) : referenceTokens = List.unmodifiable(referenceTokens),
       draftTokens = List.unmodifiable(draftTokens),
       matches = List.unmodifiable(matches);

  int get referenceTokenCount => referenceTokens.length;
  int get matchedReferenceTokenCount =>
      matches.map((match) => match.referenceIndex).toSet().length;
  double get referenceCoverage => referenceTokenCount == 0
      ? 0
      : matchedReferenceTokenCount / referenceTokenCount;
}

/// Pure-Dart token alignment. T2b will add unique anchors for repeated passages.
class ReferenceTokenAligner {
  final LyricTokenizer tokenizer;

  const ReferenceTokenAligner({this.tokenizer = const LyricTokenizer()});

  ReferenceTokenAlignmentResult align({
    required String referenceText,
    required String draftText,
  }) {
    final reference = tokenizer.tokenize(referenceText);
    final draft = tokenizer.tokenize(draftText);
    final cells = (reference.length + 1) * (draft.length + 1);
    if (cells > ProofreadConstants.maxNwCells) {
      return ReferenceTokenAlignmentResult(
        referenceTokens: reference,
        draftTokens: draft,
        matches: const [],
        dpBudgetExceeded: true,
      );
    }
    return ReferenceTokenAlignmentResult(
      referenceTokens: reference,
      draftTokens: draft,
      matches: _align(reference, draft),
      dpBudgetExceeded: false,
    );
  }

  List<TokenMatch> _align(List<String> reference, List<String> draft) {
    final rows = reference.length;
    final columns = draft.length;
    final scores = List<List<double>>.generate(
      rows + 1,
      (_) => List<double>.filled(columns + 1, 0),
      growable: false,
    );
    final moves = List<List<int>>.generate(
      rows + 1,
      (_) => List<int>.filled(columns + 1, 0),
      growable: false,
    );

    for (var i = 1; i <= rows; i++) {
      for (var j = 1; j <= columns; j++) {
        var best = scores[i - 1][j];
        var move = 1;
        if (scores[i][j - 1] > best) {
          best = scores[i][j - 1];
          move = 2;
        }
        final similarity = _tokenSimilarity(reference[i - 1], draft[j - 1]);
        if (similarity > ProofreadConstants.softMatchMinSim) {
          final paired =
              scores[i - 1][j - 1] +
              similarity -
              ProofreadConstants.softMatchMinSim;
          if (paired > best) {
            best = paired;
            move = 3;
          }
        }
        scores[i][j] = best;
        moves[i][j] = move;
      }
    }

    final result = <TokenMatch>[];
    var i = rows;
    var j = columns;
    while (i > 0 && j > 0) {
      final move = moves[i][j];
      if (move == 3) {
        result.add(
          TokenMatch(
            referenceIndex: i - 1,
            draftIndex: j - 1,
            similarity: _tokenSimilarity(reference[i - 1], draft[j - 1]),
          ),
        );
        i--;
        j--;
      } else if (move == 2) {
        j--;
      } else {
        i--;
      }
    }
    return result.reversed.toList(growable: false);
  }

  double _tokenSimilarity(String leftToken, String rightToken) {
    if (leftToken == rightToken) return 1;
    final left = leftToken.runes.toList(growable: false);
    final right = rightToken.runes.toList(growable: false);
    final maxLength = left.length >= right.length ? left.length : right.length;
    if (maxLength == 0) return 1;
    if ((left.length - right.length).abs() / maxLength >=
        1 - ProofreadConstants.softMatchMinSim) {
      return 0;
    }

    var previous = List<int>.generate(right.length + 1, (index) => index);
    var current = List<int>.filled(right.length + 1, 0);
    for (var i = 1; i <= left.length; i++) {
      current[0] = i;
      for (var j = 1; j <= right.length; j++) {
        final cost = left[i - 1] == right[j - 1] ? 0 : 1;
        current[j] = _min3(
          previous[j] + 1,
          current[j - 1] + 1,
          previous[j - 1] + cost,
        );
      }
      final swap = previous;
      previous = current;
      current = swap;
    }
    return 1 - previous[right.length] / maxLength;
  }

  static int _min3(int a, int b, int c) {
    var min = a;
    if (b < min) min = b;
    if (c < min) min = c;
    return min;
  }
}
