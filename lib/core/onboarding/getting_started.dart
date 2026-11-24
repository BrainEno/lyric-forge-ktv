/// The 开始使用 checklist shared by the desktop dashboard (D-070) and the
/// phone's 听歌 page (D-071): whether it is shown, and where a step stands.
///
/// Each platform has its own steps, worked out from its own data; this file
/// holds only what both need, so neither feature imports the other.
library;

/// Whether the checklist is shown.
enum GettingStartedVisibility {
  /// Nothing saved yet: decided on the first load of the home page.
  undecided,

  /// The card is on the home page.
  active,

  /// The user closed it; 设置 can bring it back.
  dismissed,

  /// The user finished all three steps and put it away.
  completed;

  static GettingStartedVisibility fromId(Object? id) {
    for (final value in values) {
      if (value.name == id) return value;
    }
    return undecided;
  }
}

/// What the app remembers about the checklist between launches.
///
/// Only what cannot be read from the user's data is saved: whether the card
/// is shown, and whether the user has opened KTV from it on the desktop.
/// Everything else is worked out again every time.
class GettingStartedPreferences {
  final GettingStartedVisibility visibility;

  /// The desktop's 用 KTV 模式唱一遍 step was opened from the card.
  final bool openedKtv;

  const GettingStartedPreferences({
    this.visibility = GettingStartedVisibility.undecided,
    this.openedKtv = false,
  });

  bool get showsCard => visibility == GettingStartedVisibility.active;

  /// The first decision: someone with nothing in the app yet — no projects
  /// on the desktop, no songs on a phone — is new and gets the card;
  /// someone who already has some knows the app and does not.
  GettingStartedPreferences decidedFor({required bool hasContent}) {
    if (visibility != GettingStartedVisibility.undecided) return this;
    return copyWith(
      visibility: hasContent
          ? GettingStartedVisibility.dismissed
          : GettingStartedVisibility.active,
    );
  }

  GettingStartedPreferences copyWith({
    GettingStartedVisibility? visibility,
    bool? openedKtv,
  }) {
    return GettingStartedPreferences(
      visibility: visibility ?? this.visibility,
      openedKtv: openedKtv ?? this.openedKtv,
    );
  }
}

/// Where one step stands.
enum GettingStartedStepState {
  /// Finished.
  done,

  /// Started and running on its own (recognition in progress).
  inProgress,

  /// Can be done now.
  ready,

  /// Waits for an earlier step.
  locked,
}
