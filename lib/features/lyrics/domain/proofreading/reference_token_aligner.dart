import 'lyric_tokenizer.dart';
import 'proofread_constants.dart';

class TokenMatch {
  final int referenceIndex;
  final int draftIndex;
  final double similarity;
  final bool isAnchor;

  const TokenMatch({
    required this.referenceIndex,
    required this.draftIndex,
    required this.similarity,
    this.isAnchor = false,
  });
}

class ReferenceTokenAlignmentResult {
  final List<String> referenceTokens;
  final List<String> draftTokens;
  final List<TokenMatch> matches;
  final int anchorCount;
  final bool candidateLimitReached;
  final bool dpBudgetExceeded;

  ReferenceTokenAlignmentResult({
    required List<String> referenceTokens,
    required List<String> draftTokens,
    required List<TokenMatch> matches,
    required this.anchorCount,
    required this.candidateLimitReached,
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

/// Pure-Dart token alignment using unique n-gram anchors to limit DP work.
class ReferenceTokenAligner {
  final LyricTokenizer tokenizer;

  const ReferenceTokenAligner({this.tokenizer = const LyricTokenizer()});

  ReferenceTokenAlignmentResult align({
    required String referenceText,
    required String draftText,
  }) {
    final reference = tokenizer.tokenize(referenceText);
    final draft = tokenizer.tokenize(draftText);
    final referenceOccurrences = _anchorOccurrences(reference);
    final draftOccurrences = _anchorOccurrences(draft);
    final candidates = <_Anchor>[];
    var candidateLimitReached = false;

    for (final entry in referenceOccurrences.entries) {
      final referencePositions = entry.value;
      final draftPositions = draftOccurrences[entry.key];
      if (referencePositions.length != 1 ||
          draftPositions == null ||
          draftPositions.length != 1) {
        continue;
      }
      if (candidates.length >= ProofreadConstants.maxChainCandidates) {
        candidateLimitReached = true;
        candidates.clear();
        break;
      }
      final isCjk = entry.key.startsWith('c:');
      candidates.add(
        _Anchor(
          referencePositions.single,
          draftPositions.single,
          isCjk
              ? ProofreadConstants.anchorKCjk
              : ProofreadConstants.anchorKLatin,
        ),
      );
    }

    candidates.sort((a, b) {
      final byReference = a.referenceStart.compareTo(b.referenceStart);
      return byReference != 0
          ? byReference
          : a.draftStart.compareTo(b.draftStart);
    });
    final anchors = candidateLimitReached
        ? <_Anchor>[]
        : _selectAnchorChain(candidates);
    final gaps = _buildGaps(anchors, reference.length, draft.length);
    var dpCells = 0;
    var dpBudgetExceeded = false;
    for (final gap in gaps) {
      final referenceLength = gap.referenceEnd - gap.referenceStart;
      final draftLength = gap.draftEnd - gap.draftStart;
      if (referenceLength == 0 || draftLength == 0) continue;
      final needed = (referenceLength + 1) * (draftLength + 1);
      if (needed > ProofreadConstants.maxNwCells - dpCells) {
        dpBudgetExceeded = true;
        break;
      }
      dpCells += needed;
    }

    final matches = <TokenMatch>[];
    for (final anchor in anchors) {
      for (var offset = 0; offset < anchor.length; offset++) {
        matches.add(
          TokenMatch(
            referenceIndex: anchor.referenceStart + offset,
            draftIndex: anchor.draftStart + offset,
            similarity: 1,
            isAnchor: true,
          ),
        );
      }
    }
    if (!dpBudgetExceeded) {
      for (final gap in gaps) {
        final gapMatches = _align(
          reference.sublist(gap.referenceStart, gap.referenceEnd),
          draft.sublist(gap.draftStart, gap.draftEnd),
        );
        matches.addAll(
          gapMatches.map(
            (match) => TokenMatch(
              referenceIndex: match.referenceIndex + gap.referenceStart,
              draftIndex: match.draftIndex + gap.draftStart,
              similarity: match.similarity,
            ),
          ),
        );
      }
    }
    matches.sort((a, b) => a.referenceIndex.compareTo(b.referenceIndex));

    return ReferenceTokenAlignmentResult(
      referenceTokens: reference,
      draftTokens: draft,
      matches: matches,
      anchorCount: anchors.length,
      candidateLimitReached: candidateLimitReached,
      dpBudgetExceeded: dpBudgetExceeded,
    );
  }

  Map<String, List<int>> _anchorOccurrences(List<String> tokens) {
    final result = <String, List<int>>{};
    for (var start = 0; start < tokens.length; start++) {
      final isCjk = tokenizer.isCjkToken(tokens[start]);
      final length = isCjk
          ? ProofreadConstants.anchorKCjk
          : ProofreadConstants.anchorKLatin;
      if (start + length > tokens.length) continue;

      var sameScript = true;
      for (var offset = 1; offset < length; offset++) {
        if (tokenizer.isCjkToken(tokens[start + offset]) != isCjk) {
          sameScript = false;
          break;
        }
      }
      if (!sameScript) continue;

      final prefix = isCjk ? 'c' : 'l';
      final key = '$prefix:${tokens.sublist(start, start + length).join('|')}';
      final positions = result.putIfAbsent(key, () => <int>[]);
      // Keep one overflow occurrence so repeated windows cannot look unique.
      if (positions.length <= ProofreadConstants.maxOccurrencesPerKey) {
        positions.add(start);
      }
    }
    return result;
  }

  List<_Anchor> _selectAnchorChain(List<_Anchor> candidates) {
    if (candidates.isEmpty) return <_Anchor>[];
    final scores = List<int>.filled(candidates.length, 0);
    final previous = List<int>.filled(candidates.length, -1);
    var bestIndex = 0;

    for (var i = 0; i < candidates.length; i++) {
      scores[i] = candidates[i].length;
      for (var j = 0; j < i; j++) {
        final before = candidates[j];
        final current = candidates[i];
        if (before.referenceStart + before.length > current.referenceStart ||
            before.draftStart + before.length > current.draftStart) {
          continue;
        }
        final score = scores[j] + current.length;
        if (score > scores[i]) {
          scores[i] = score;
          previous[i] = j;
        }
      }
      if (scores[i] > scores[bestIndex]) bestIndex = i;
    }

    final chain = <_Anchor>[];
    var index = bestIndex;
    while (true) {
      chain.add(candidates[index]);
      final next = previous[index];
      if (next < 0) break;
      index = next;
    }
    return chain.reversed.toList(growable: false);
  }

  List<_TokenGap> _buildGaps(
    List<_Anchor> anchors,
    int referenceLength,
    int draftLength,
  ) {
    final gaps = <_TokenGap>[];
    var referenceStart = 0;
    var draftStart = 0;
    for (final anchor in anchors) {
      if (referenceStart < anchor.referenceStart &&
          draftStart < anchor.draftStart) {
        gaps.add(
          _TokenGap(
            referenceStart,
            anchor.referenceStart,
            draftStart,
            anchor.draftStart,
          ),
        );
      }
      referenceStart = anchor.referenceStart + anchor.length;
      draftStart = anchor.draftStart + anchor.length;
    }
    if (referenceStart < referenceLength && draftStart < draftLength) {
      gaps.add(
        _TokenGap(referenceStart, referenceLength, draftStart, draftLength),
      );
    }
    if (anchors.isEmpty && referenceLength > 0 && draftLength > 0) {
      gaps.add(_TokenGap(0, referenceLength, 0, draftLength));
    }
    return gaps;
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

class _Anchor {
  final int referenceStart;
  final int draftStart;
  final int length;
  const _Anchor(this.referenceStart, this.draftStart, this.length);
}

class _TokenGap {
  final int referenceStart;
  final int referenceEnd;
  final int draftStart;
  final int draftEnd;
  const _TokenGap(
    this.referenceStart,
    this.referenceEnd,
    this.draftStart,
    this.draftEnd,
  );
}
