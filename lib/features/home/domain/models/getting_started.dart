import '../../../project/domain/models/lyric_review_overview.dart';
import '../../../project/domain/models/project_manifest.dart';

/// Whether the dashboard shows the 开始使用 checklist (D-070).
enum GettingStartedVisibility {
  /// Nothing saved yet: decided on the first dashboard load.
  undecided,

  /// The card is on the dashboard.
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
/// Only what cannot be read from the projects is saved: whether the card is
/// shown, and whether the user has opened KTV from it. Importing and review
/// are worked out from the projects every time.
class GettingStartedPreferences {
  final GettingStartedVisibility visibility;

  /// The user opened a project's player from the 用 KTV 模式唱一遍 step.
  final bool openedKtv;

  const GettingStartedPreferences({
    this.visibility = GettingStartedVisibility.undecided,
    this.openedKtv = false,
  });

  bool get showsCard => visibility == GettingStartedVisibility.active;

  /// The first decision: someone with no projects is new and gets the card;
  /// someone who already has projects knows the app and does not.
  GettingStartedPreferences decidedFor({required bool hasProjects}) {
    if (visibility != GettingStartedVisibility.undecided) return this;
    return copyWith(
      visibility: hasProjects
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

/// The three steps from a song to singing it.
enum GettingStartedStep { importSong, reviewLyrics, singKtv }

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

/// How far the user has got, worked out from their projects.
class GettingStartedProgress {
  /// The newest project still waiting for lyrics, while none has any.
  final ProjectManifest? recognizing;

  /// The newest project with lyrics: where 校对 and KTV take the user.
  final ProjectManifest? lyricsProject;

  /// Some project has a line a person confirmed.
  final bool reviewed;

  final bool openedKtv;

  const GettingStartedProgress({
    this.recognizing,
    this.lyricsProject,
    this.reviewed = false,
    this.openedKtv = false,
  });

  /// Progress from [projects], newest first as the repository returns them.
  ///
  /// [countReview] is the lyric editor's counter (D-069); without it the
  /// review step only completes once the app can count.
  factory GettingStartedProgress.from(
    List<ProjectManifest> projects, {
    ProjectLyricReviewCounter? countReview,
    bool openedKtv = false,
  }) {
    ProjectManifest? lyricsProject;
    for (final project in projects) {
      if (project.hasLyrics) {
        lyricsProject = project;
        break;
      }
    }
    var reviewed = false;
    if (countReview != null) {
      for (final project in projects) {
        if (project.hasLyrics && countReview(project).reviewed > 0) {
          reviewed = true;
          break;
        }
      }
    }
    return GettingStartedProgress(
      recognizing: lyricsProject == null && projects.isNotEmpty
          ? projects.first
          : null,
      lyricsProject: lyricsProject,
      reviewed: reviewed,
      openedKtv: openedKtv,
    );
  }

  bool get recognized => lyricsProject != null;

  GettingStartedStepState stateOf(GettingStartedStep step) {
    switch (step) {
      case GettingStartedStep.importSong:
        if (recognized) return GettingStartedStepState.done;
        return recognizing != null
            ? GettingStartedStepState.inProgress
            : GettingStartedStepState.ready;
      case GettingStartedStep.reviewLyrics:
        if (reviewed) return GettingStartedStepState.done;
        return recognized
            ? GettingStartedStepState.ready
            : GettingStartedStepState.locked;
      case GettingStartedStep.singKtv:
        if (openedKtv) return GettingStartedStepState.done;
        return recognized
            ? GettingStartedStepState.ready
            : GettingStartedStepState.locked;
    }
  }

  int get doneCount => GettingStartedStep.values
      .where((step) => stateOf(step) == GettingStartedStepState.done)
      .length;

  bool get allDone => doneCount == GettingStartedStep.values.length;

  /// The first step not done yet; its button is the prominent one.
  GettingStartedStep? get next {
    for (final step in GettingStartedStep.values) {
      if (stateOf(step) != GettingStartedStepState.done) return step;
    }
    return null;
  }
}
