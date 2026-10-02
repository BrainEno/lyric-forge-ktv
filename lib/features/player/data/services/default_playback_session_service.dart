import 'dart:async';

import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_session_service.dart';

class DefaultPlaybackSessionService implements PlaybackSessionService {
  final AudioPlayerService _audioPlayer;
  final _stateController =
      StreamController<PlaybackSessionState>.broadcast();

  PlaybackSessionState _state = const PlaybackSessionState();
  StreamSubscription<PlaybackState>? _playbackSubscription;
  bool _handledCompletion = false;

  DefaultPlaybackSessionService(this._audioPlayer) {
    _playbackSubscription = _audioPlayer.stateStream.listen((playback) {
      if (!playback.isCompleted) {
        _handledCompletion = false;
        return;
      }
      if (_handledCompletion) return;
      _handledCompletion = true;
      if (_state.canSkipNext) {
        unawaited(skipNext());
      }
    });
  }

  @override
  Stream<PlaybackSessionState> get stateStream => _stateController.stream;

  @override
  PlaybackSessionState get currentState => _state;

  @override
  PlaybackState get playbackState => _audioPlayer.currentState;

  void _emit(PlaybackSessionState next) {
    _state = next;
    _stateController.add(_state);
  }

  Future<void> _loadCurrent({Duration? resumeFrom}) async {
    final item = _state.currentItem;
    if (item == null) return;

    await _audioPlayer.loadProjectAudio(
      audioAsset: item.audioAsset,
      preferredSource: item.preferredSource,
    );

    if (resumeFrom != null && resumeFrom > Duration.zero) {
      final duration = _audioPlayer.currentState.duration;
      if (duration == null || resumeFrom < duration) {
        await _audioPlayer.seek(resumeFrom);
      }
    }

    await _audioPlayer.play();
  }

  @override
  Future<void> playItem(
    PlaybackItem item, {
    Duration? resumeFrom,
  }) async {
    final queue = List<PlaybackItem>.from(_state.queue);
    var index = queue.indexWhere((entry) => entry.id == item.id);

    if (index >= 0) {
      queue[index] = item;
    } else {
      queue.add(item);
      index = queue.length - 1;
    }

    _emit(PlaybackSessionState(queue: queue, currentIndex: index));
    _handledCompletion = false;
    await _loadCurrent(resumeFrom: resumeFrom);
  }

  @override
  Future<void> setQueue(
    List<PlaybackItem> items, {
    int startIndex = 0,
  }) async {
    if (items.isEmpty) {
      _emit(const PlaybackSessionState());
      await _audioPlayer.stop();
      return;
    }

    final safeIndex = startIndex.clamp(0, items.length - 1);
    _emit(
      PlaybackSessionState(
        queue: List<PlaybackItem>.unmodifiable(items),
        currentIndex: safeIndex,
      ),
    );
    _handledCompletion = false;
    await _loadCurrent();
  }

  @override
  Future<void> enqueue(PlaybackItem item) async {
    final queue = List<PlaybackItem>.from(_state.queue);
    if (queue.every((entry) => entry.id != item.id)) {
      queue.add(item);
      _emit(
        PlaybackSessionState(
          queue: queue,
          currentIndex: _state.currentIndex,
        ),
      );
    }
  }

  @override
  Future<void> skipPrevious() async {
    if (_state.currentItem == null) return;

    if (_audioPlayer.currentState.position > const Duration(seconds: 3)) {
      await _audioPlayer.seek(Duration.zero);
      return;
    }

    if (_state.currentIndex <= 0) {
      await _audioPlayer.seek(Duration.zero);
      return;
    }

    _emit(
      PlaybackSessionState(
        queue: _state.queue,
        currentIndex: _state.currentIndex - 1,
      ),
    );
    _handledCompletion = false;
    await _loadCurrent();
  }

  @override
  Future<void> skipNext() async {
    if (!_state.canSkipNext) return;

    _emit(
      PlaybackSessionState(
        queue: _state.queue,
        currentIndex: _state.currentIndex + 1,
      ),
    );
    _handledCompletion = false;
    await _loadCurrent();
  }

  @override
  Future<void> togglePlayPause() async {
    if (_audioPlayer.currentState.isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  @override
  Future<void> seek(Duration position) => _audioPlayer.seek(position);

  @override
  Future<void> dispose() async {
    await _playbackSubscription?.cancel();
    await _stateController.close();
  }
}
