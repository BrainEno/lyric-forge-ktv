import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/onboarding/getting_started.dart';
import 'package:lyric_forge_ktv/core/onboarding/getting_started_store.dart';

void main() {
  group('first decision (D-070, D-071)', () {
    test('someone with nothing in the app yet gets the checklist', () {
      final decided = const GettingStartedPreferences().decidedFor(
        hasContent: false,
      );
      expect(decided.visibility, GettingStartedVisibility.active);
      expect(decided.showsCard, isTrue);
    });

    test('someone who already has projects or songs does not', () {
      final decided = const GettingStartedPreferences().decidedFor(
        hasContent: true,
      );
      expect(decided.visibility, GettingStartedVisibility.dismissed);
      expect(decided.showsCard, isFalse);
    });

    test('a saved choice is never decided again', () {
      const closed = GettingStartedPreferences(
        visibility: GettingStartedVisibility.dismissed,
      );
      expect(
        closed.decidedFor(hasContent: false).visibility,
        GettingStartedVisibility.dismissed,
      );
    });

    test('unknown saved values read as undecided', () {
      expect(
        GettingStartedVisibility.fromId('later'),
        GettingStartedVisibility.undecided,
      );
      expect(
        GettingStartedVisibility.fromId('completed'),
        GettingStartedVisibility.completed,
      );
    });
  });

  test('设置 brings the card back and keeps what was done', () async {
    final store = MemoryGettingStartedStore(
      const GettingStartedPreferences(
        visibility: GettingStartedVisibility.completed,
        openedKtv: true,
      ),
    );

    await showGettingStartedAgain(store);

    expect(store.saved?.visibility, GettingStartedVisibility.active);
    expect(store.saved?.openedKtv, isTrue);
  });
}
