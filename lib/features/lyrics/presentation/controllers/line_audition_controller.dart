import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../player/domain/services/audio_player_service.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_audition_window_service.dart';

/// One bounded audition of a single lyric line (or of one timed word in it).
@immutable
class LineAuditionRequest {
  final String projectId;
  final int lineIndex;

  /// Stable line identity. When present the audition follows the line through
  /// insertions, deletions and reordering instead of drifting to another row.
  final String? lineId;

  final LyricAuditionWindow window;

  const LineAuditionRequest({
    required this.projectId,
    required this.lineIndex,
    required this.lineId,
    required this.window,
  });

  bool belongsTo(String? otherProjectId) => projectId == otherProjectId;

  bool isSameLineAs(LineAuditionRequest other) {
    if (projectId != other.projectId) return false;
    if (lineId != null) return lineId == other.lineId;
    return lineIndex == other.lineIndex;
  }

  bool hasSameWindowAs(LineAuditionRequest other) =>
      window.startAt == other.window.startAt &&
      window.endAt == other.window.endAt;
}

enum LineAuditionAction {
  /// A new bounded window started playing.
  started,

  /// Playback resumed inside the same window.
  resumed,

  /// Playback was paused by the same button that started it.
  paused,

  /// The window is not usable (invalid or out-of-range timestamps).
  invalid,

  /// Playback could not be started; [LineAuditionResult.error] says why.
  failed,
}

@immutable
class LineAuditionResult {
  final LineAuditionAction action;
  final String? error;

  const LineAuditionResult(this.action, [this.error]);

  const LineAuditionResult.started()
    : action = LineAuditionAction.started,
      error = null;
  const LineAuditionResult.resumed()
    : action = LineAuditionAction.resumed,
      error = null;
  const LineAuditionResult.paused()
    : action = LineAuditionAction.paused,
      error = null;
  const LineAuditionResult.invalid()
    : action = LineAuditionAction.invalid,
      error = null;
  LineAuditionResult.failed(this.error) : action = LineAuditionAction.failed;

  bool get succeeded => action != LineAuditionAction.failed;
}

/// Owns the editor's bounded line audition: which window is playing, whether it
/// loops, and what has to happen when playback reaches the window edge.
///
/// This used to live inside a 2,000-line `State`, where the interesting rules —
/// "pause at the end, unless looping, in which case jump back to the start",
/// "ignore a second edge event while the first is still in flight", "drop the
/// highlight when the queue moves to another project" — could only be exercised
/// by driving the whole editor widget.
///
/// The controller never loads project audio itself; [prepare] is supplied by the
/// caller so the queue keeps being built where the project manifest is known.
class LineAuditionController extends ChangeNotifier {
  LineAuditionController({
    required AudioPlayerService audioService,
    required PlaybackSessionService playbackSession,
    required void Function(Object error) onBoundaryError,
  }) : _audioService = audioService,
       _playbackSession = playbackSession,
       _onBoundaryError = onBoundaryError {
    _positionSubscription = _audioService.positionStream.listen(
      _handlePosition,
    );
  }

  final AudioPlayerService _audioService;
  final PlaybackSessionService _playbackSession;
  final void Function(Object error) _onBoundaryError;

  StreamSubscription<Duration>? _positionSubscription;
  LineAuditionRequest? _active;
  bool Function()? _activePlaybackValid;
  bool _loopEnabled = false;
  bool _boundaryActionInFlight = false;

  /// A boundary action can still be in flight when the editor closes; notifying
  /// listeners after [dispose] would throw.
  bool _disposed = false;

  LineAuditionRequest? get active => _active;

  bool get isActive => _active != null;

  bool get loopEnabled => _loopEnabled;

  set loopEnabled(bool value) {
    if (_loopEnabled == value) return;
    _loopEnabled = value;
    _notify();
  }

  /// Index of the active line inside [document], or null when the audition
  /// belongs to another project, playback has moved on, or the line is gone.
  int? activeLineIndex(LyricDocument? document) {
    final active = _active;
    if (active == null || document == null) return null;
    if (!active.belongsTo(
      _playbackSession.currentState.currentItem?.projectId,
    )) {
      return null;
    }
    final lineId = active.lineId;
    if (lineId != null) {
      for (var index = 0; index < document.lines.length; index++) {
        if (document.lines[index].id == lineId) return index;
      }
      return null;
    }
    return active.lineIndex >= 0 && active.lineIndex < document.lines.length
        ? active.lineIndex
        : null;
  }

  /// Drops the active window without touching playback.
  void clear() {
    if (_active == null) return;
    _active = null;
    _activePlaybackValid = null;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// True when the active audition belongs to the loaded project and is the
  /// thing currently producing sound — i.e. clearing it should also pause.
  bool get isSounding {
    final active = _active;
    if (active == null) return false;
    if (!active.belongsTo(
      _playbackSession.currentState.currentItem?.projectId,
    )) {
      return false;
    }
    return _audioService.currentState.isPlaying;
  }

  /// Pauses playback when the active audition is the thing currently sounding.
  Future<void> pauseIfSounding() async {
    final active = _active;
    if (active == null) return;
    if (!active.belongsTo(
      _playbackSession.currentState.currentItem?.projectId,
    )) {
      return;
    }
    if (!_audioService.currentState.isPlaying) return;
    await _audioService.pause();
  }

  /// Row-button semantics: pause or resume the same window, otherwise start it.
  Future<LineAuditionResult> toggle({
    required LineAuditionRequest request,
    required Future<void> Function() prepare,
    bool Function()? isStillValid,
    bool Function()? isPlaybackStillValid,
  }) async {
    if (isStillValid != null && !isStillValid()) {
      return LineAuditionResult.failed('试听条件已变化，请重试。');
    }
    var active = _active;
    if (active != null && _activePlaybackValid != null && !_activePlaybackValid!()) {
      clear();
      active = null;
    }
    final playbackBelongsToProject = request.belongsTo(
      _playbackSession.currentState.currentItem?.projectId,
    );
    if (active != null &&
        active.isSameLineAs(request) &&
        active.hasSameWindowAs(request) &&
        playbackBelongsToProject) {
      final playback = _audioService.currentState;
      if (playback.isPlaying) {
        await _audioService.pause();
        return const LineAuditionResult.paused();
      }
      final endAt = active.window.endAt;
      final canResume =
          playback.position >= active.window.startAt &&
          (endAt == null || playback.position < endAt);
      if (canResume) {
        await _audioService.play();
        return const LineAuditionResult.resumed();
      }
    }
    return start(
      request: request,
      prepare: prepare,
      isStillValid: isStillValid,
      isPlaybackStillValid: isPlaybackStillValid,
    );
  }

  /// Starts the window from its lead-in position.
  Future<LineAuditionResult> start({
    required LineAuditionRequest request,
    required Future<void> Function() prepare,
    bool Function()? isStillValid,
    bool Function()? isPlaybackStillValid,
  }) async {
    if (isStillValid != null && !isStillValid()) {
      return LineAuditionResult.failed('试听条件已变化，请重试。');
    }
    if (!request.window.canAudition) {
      // Pause first, then drop the window: pauseIfSounding needs to know which
      // project the sounding audition belonged to.
      await pauseIfSounding();
      clear();
      return const LineAuditionResult.invalid();
    }

    try {
      if (!request.belongsTo(
        _playbackSession.currentState.currentItem?.projectId,
      )) {
        await prepare();
      }

      if (isStillValid != null && !isStillValid()) {
        return LineAuditionResult.failed('试听条件已变化，请重试。');
      }
      await _playbackSession.seek(request.window.startAt);
      if (isStillValid != null && !isStillValid()) {
        return LineAuditionResult.failed('试听条件已变化，请重试。');
      }
      _active = request;
      _activePlaybackValid = isPlaybackStillValid;
      _notify();
      if (!_audioService.currentState.isPlaying) {
        await _audioService.play();
      }
      if (!_audioService.currentState.isPlaying) {
        return LineAuditionResult.failed('播放器未进入播放状态；请检查音频文件与播放器日志。');
      }
      return const LineAuditionResult.started();
    } catch (error) {
      if (_active != null) clear();
      return LineAuditionResult.failed(error.toString());
    }
  }

  void _handlePosition(Duration position) {
    final active = _active;
    final endAt = active?.window.endAt;
    if (active == null || endAt == null) return;

    if (!active.belongsTo(
          _playbackSession.currentState.currentItem?.projectId,
        ) || (_activePlaybackValid != null && !_activePlaybackValid!())) {
      clear();
      return;
    }

    final playback = _audioService.currentState;
    final reachedNaturalEndWhileLooping = _loopEnabled && playback.isCompleted;
    if (_boundaryActionInFlight ||
        (!playback.isPlaying && !reachedNaturalEndWhileLooping) ||
        position < endAt) {
      return;
    }

    _boundaryActionInFlight = true;
    unawaited(_handleBoundary(active));
  }

  Future<void> _handleBoundary(LineAuditionRequest active) async {
    try {
      final playback = _audioService.currentState;
      final reachedNaturalEndWhileLooping =
          _loopEnabled && playback.isCompleted;
      if (_disposed ||
          !identical(_active, active) ||
          (_activePlaybackValid != null && !_activePlaybackValid!()) ||
          !active.belongsTo(
            _playbackSession.currentState.currentItem?.projectId,
          ) ||
          (!playback.isPlaying && !reachedNaturalEndWhileLooping)) {
        return;
      }

      if (_loopEnabled && active.window.endAt != null) {
        await _playbackSession.seek(active.window.startAt);
        if (_disposed ||
            !identical(_active, active) ||
            (_activePlaybackValid != null && !_activePlaybackValid!()) ||
            !active.belongsTo(
              _playbackSession.currentState.currentItem?.projectId,
            )) {
          return;
        }
        if (_loopEnabled) {
          if (!_audioService.currentState.isPlaying) {
            await _audioService.play();
          }
        } else if (_audioService.currentState.isPlaying) {
          await _audioService.pause();
        }
      } else if (_audioService.currentState.isPlaying) {
        await _audioService.pause();
      }
    } catch (error) {
      if (!_disposed) _onBoundaryError(error);
    } finally {
      _boundaryActionInFlight = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_positionSubscription?.cancel() ?? Future<void>.value());
    _positionSubscription = null;
    super.dispose();
  }
}
