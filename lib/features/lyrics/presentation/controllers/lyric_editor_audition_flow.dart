import '../../../player/domain/services/audio_player_service.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../domain/proofreading/proofread_result.dart';
import '../../domain/services/lyric_audition_window_service.dart';
import '../lyric_review_strings.dart';
import '../widgets/lyric_proofread_dialog.dart';
import 'line_audition_controller.dart';

/// The editor's audio: auditioning a row, a proposed line or a word, and the
/// editor-wide play / pause and seek (D-073).
///
/// Every audition loads the project into the shared queue first when the queue
/// is showing something else, then plays a bounded window worked out from the
/// lyric timestamps, the document's global offset and the audio's length. The
/// screen keeps the state it shows; this keeps the audio rules.
class LyricEditorAuditionFlow {
  LyricEditorAuditionFlow({
    required this.audition,
    required this.audioService,
    required this.playbackSession,
    required this.document,
    required this.isMounted,
    required this.selectLine,
    required this.showMessage,
  });

  final LineAuditionController audition;
  final AudioPlayerService audioService;
  final PlaybackSessionService playbackSession;

  /// The document being edited, read at the moment of each call.
  final LyricDocument? Function() document;

  /// Whether the editor is still on screen; nothing is shown once it is not.
  final bool Function() isMounted;

  /// Selects the row an audition started on.
  final void Function(int index) selectLine;

  /// Shows a short message to the user.
  final void Function(String message) showMessage;

  static const String _unplayable = '该时间范围超出音频有效时长或时间区间无效，无法试听。';

  /// The queue entry that plays [project]'s own audio, the vocal stem first
  /// when there is one.
  static PlaybackItem playbackItemFor(
    ProjectManifest project,
    AudioAsset audioAsset,
  ) => PlaybackItem(
    id: 'project:${project.id}',
    title: project.name,
    artist: project.artist,
    projectId: project.id,
    artworkPath: audioAsset.thumbnailPath,
    hasLyrics: project.hasLyrics,
    audioAsset: audioAsset,
    preferredSource: audioAsset.vocalPath != null
        ? AudioSourceType.vocals
        : AudioSourceType.original,
  );

  /// How long [project]'s audio is: what the player measured while it is
  /// playing this project ([current] is the queue's song), else what the
  /// project stored.
  static Duration? audioDurationFor(
    ProjectManifest project,
    AudioAsset audioAsset, {
    required PlaybackItem? current,
    required Duration? playerDuration,
  }) => current?.projectId == project.id
      ? (playerDuration ?? audioAsset.duration)
      : audioAsset.duration;

  /// The audio-time window for a span of [project]'s lyrics.
  LyricAuditionWindow windowFor(
    ProjectManifest project,
    AudioAsset audioAsset, {
    required Duration start,
    required Duration? end,
    required Duration globalOffset,
    Duration preRoll = LyricAuditionWindowService.defaultPreRoll,
  }) {
    return const LyricAuditionWindowService().calculate(
      lineStart: start,
      lineEnd: end,
      globalOffset: globalOffset,
      audioDuration: audioDurationFor(
        project,
        audioAsset,
        current: playbackSession.currentState.currentItem,
        playerDuration: audioService.currentState.duration,
      ),
      preRoll: preRoll,
    );
  }

  /// The row button: plays row [index], or pauses / resumes it when it is
  /// the one already playing.
  Future<void> previewLine(ProjectManifest project, int index) async {
    final document = this.document();
    final audioAsset = project.audioAsset;
    if (document == null ||
        audioAsset == null ||
        index < 0 ||
        index >= document.lines.length) {
      return;
    }

    final line = document.lines[index];
    final window = windowFor(
      project,
      audioAsset,
      start: line.startTime,
      end: line.endTime,
      globalOffset: document.globalOffset ?? Duration.zero,
    );

    try {
      final result = await audition.toggle(
        request: _request(project, document, index, window),
        prepare: () => _prepare(project, audioAsset),
      );
      if (!isMounted()) return;
      switch (result.action) {
        case LineAuditionAction.started:
          selectLine(index);
        case LineAuditionAction.invalid:
          showMessage(LyricReviewStrings.auditionInvalidStart);
        case LineAuditionAction.failed:
          showMessage(
            '${LyricReviewStrings.auditionErrorPrefix}${result.error}',
          );
        case LineAuditionAction.paused:
        case LineAuditionAction.resumed:
          break;
      }
    } catch (error) {
      if (!isMounted()) return;
      showMessage('${LyricReviewStrings.auditionErrorPrefix}$error');
    }
  }

  /// A proofreading proposal's version of row [index]: [line] under
  /// [globalOffset], which may differ from the document's. The dialog shows
  /// the result itself, so nothing is shown here.
  Future<ProofreadTimedLinePreviewResult> previewTimedLine(
    ProjectManifest project,
    int index,
    LyricLine line,
    Duration globalOffset,
  ) async {
    final document = this.document();
    final audioAsset = project.audioAsset;
    if (document == null ||
        audioAsset == null ||
        index < 0 ||
        index >= document.lines.length) {
      return const ProofreadTimedLinePreviewResult.failure('工程音频或原始歌词行不可用。');
    }

    final window = windowFor(
      project,
      audioAsset,
      start: line.startTime,
      end: line.endTime,
      globalOffset: globalOffset,
    );
    if (!window.canAudition) {
      final error = await _start(
        project,
        index,
        document,
        audioAsset,
        window,
        showError: false,
      );
      return ProofreadTimedLinePreviewResult.failure(error ?? _unplayable);
    }

    try {
      final result = await audition.toggle(
        request: _request(project, document, index, window),
        prepare: () => _prepare(project, audioAsset),
      );
      return switch (result.action) {
        LineAuditionAction.paused =>
          const ProofreadTimedLinePreviewResult.success(message: '已暂停试听。'),
        LineAuditionAction.resumed =>
          audioService.currentState.isPlaying
              ? const ProofreadTimedLinePreviewResult.success()
              : const ProofreadTimedLinePreviewResult.failure(
                  '播放器未恢复播放状态；请检查音频文件与播放器日志。',
                ),
        LineAuditionAction.invalid => ProofreadTimedLinePreviewResult.failure(
          LyricReviewStrings.auditionInvalidStart,
        ),
        LineAuditionAction.failed => ProofreadTimedLinePreviewResult.failure(
          result.error ?? _unplayable,
        ),
        LineAuditionAction.started =>
          result.error == null
              ? const ProofreadTimedLinePreviewResult.success()
              : ProofreadTimedLinePreviewResult.failure(result.error!),
      };
    } catch (error) {
      return ProofreadTimedLinePreviewResult.failure(error.toString());
    }
  }

  /// One recognised word of row [lineIndex], with a short lead-in so its
  /// onset is heard in context.
  Future<void> previewToken(
    ProjectManifest project,
    int lineIndex,
    TimedLyricToken token,
  ) async {
    final document = this.document();
    final audioAsset = project.audioAsset;
    if (document == null ||
        audioAsset == null ||
        lineIndex < 0 ||
        lineIndex >= document.lines.length) {
      return;
    }

    final window = windowFor(
      project,
      audioAsset,
      start: token.interval.start,
      end: token.interval.end,
      globalOffset: document.globalOffset ?? Duration.zero,
      preRoll: const Duration(milliseconds: 250),
    );
    await _start(project, lineIndex, document, audioAsset, window);
  }

  /// The editor-wide play / pause. Before this project is in the queue it
  /// auditions the selected row (row 1 without one); after a bounded audition
  /// has run out it resumes the whole track.
  Future<void> togglePlayback(
    ProjectManifest project, {
    required int? selectedLineIndex,
  }) async {
    try {
      final currentItem = playbackSession.currentState.currentItem;
      if (currentItem?.projectId != project.id) {
        await previewLine(project, selectedLineIndex ?? 0);
        return;
      }

      final active = audition.active;
      final playback = audioService.currentState;
      if (active != null &&
          !playback.isPlaying &&
          active.window.endAt != null &&
          playback.position >= active.window.endAt!) {
        // The row button remains the replay action.
        audition.clear();
      }
      await playbackSession.togglePlayPause();
    } catch (error) {
      if (!isMounted()) return;
      showMessage('无法控制试听：$error');
    }
  }

  /// Seeks inside the editor. Pauses first, so playback does not run past the
  /// target while the user drags.
  Future<void> seek(Duration position) async {
    try {
      if (audition.isActive && isMounted()) audition.clear();
      if (audioService.currentState.isPlaying) await audioService.pause();
      await playbackSession.seek(position);
    } catch (error) {
      if (!isMounted()) return;
      showMessage('无法跳转试听：$error');
    }
  }

  /// Starts [window] on row [index]. Returns the error, or null when it
  /// played; shows the error too unless [showError] is false.
  Future<String?> _start(
    ProjectManifest project,
    int index,
    LyricDocument document,
    AudioAsset audioAsset,
    LyricAuditionWindow window, {
    bool showError = true,
  }) async {
    final result = await audition.start(
      request: _request(project, document, index, window),
      prepare: () => _prepare(project, audioAsset),
    );
    if (!isMounted()) return result.error ?? '校对页面已关闭。';

    switch (result.action) {
      case LineAuditionAction.started:
        selectLine(index);
        return null;
      case LineAuditionAction.invalid:
        if (showError) showMessage(LyricReviewStrings.auditionInvalidStart);
        return LyricReviewStrings.auditionInvalidStart;
      case LineAuditionAction.failed:
        if (showError) {
          showMessage(
            '${LyricReviewStrings.auditionErrorPrefix}${result.error}',
          );
        }
        return result.error;
      case LineAuditionAction.paused:
      case LineAuditionAction.resumed:
        return null;
    }
  }

  static LineAuditionRequest _request(
    ProjectManifest project,
    LyricDocument document,
    int index,
    LyricAuditionWindow window,
  ) => LineAuditionRequest(
    projectId: project.id,
    lineIndex: index,
    lineId: document.lines[index].id,
    window: window,
  );

  /// Loads [project] into the queue, so an audition seeks inside the right
  /// audio.
  Future<void> _prepare(ProjectManifest project, AudioAsset audioAsset) =>
      playbackSession.playItem(playbackItemFor(project, audioAsset));
}
