import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/playback_queue_panel.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

PlaybackItem _item(String id) => PlaybackItem(
  id: id,
  title: id,
  audioAsset: AudioAsset(originalPath: '/music/$id.mp3', format: 'mp3'),
);

void main() {
  List<String> ids(_Session session) =>
      session.state.queue.map((item) => item.id).toList();

  test('a removed song goes back to its place', () async {
    final session = _Session(['a', 'b', 'c', 'd'], current: 1);
    await session.removeAt(2);
    await restoreQueueItems(session, [(index: 2, item: _item('c'))]);
    expect(ids(session), ['a', 'b', 'c', 'd']);
    expect(session.state.currentItem?.id, 'b');
  });

  test('clearing what is up next comes back in order', () async {
    final session = _Session(['a', 'b', 'c', 'd'], current: 2);
    final removed = [
      for (final index in [0, 1, 3])
        (index: index, item: session.state.queue[index]),
    ];
    await session.clearQueue();
    expect(ids(session), ['c']);

    await restoreQueueItems(session, removed);
    expect(ids(session), ['a', 'b', 'c', 'd']);
    expect(session.state.currentItem?.id, 'c');
  });

  test('a cleared queue comes back without playing', () async {
    final session = _Session(['a', 'b'], current: 0);
    final removed = [
      for (var index = 0; index < 2; index++)
        (index: index, item: session.state.queue[index]),
    ];
    await session.clearQueue(keepCurrent: false);
    await restoreQueueItems(session, removed);
    expect(ids(session), ['a', 'b']);
    expect(session.state.currentIndex, -1);
  });
}

/// Queue moves with the real session's index rules.
class _Session extends Fake implements PlaybackSessionService {
  _Session(List<String> ids, {required int current})
    : state = PlaybackSessionState(
        queue: [for (final id in ids) _item(id)],
        currentIndex: current,
      );

  PlaybackSessionState state;

  @override
  PlaybackSessionState get currentState => state;

  @override
  Future<void> enqueue(PlaybackItem item) async {
    if (state.queue.any((entry) => entry.id == item.id)) return;
    state = state.copyWith(queue: [...state.queue, item]);
  }

  @override
  Future<void> removeAt(int index) async {
    final queue = [...state.queue]..removeAt(index);
    final current = state.currentIndex > index
        ? state.currentIndex - 1
        : state.currentIndex;
    state = state.copyWith(queue: queue, currentIndex: current);
  }

  @override
  Future<void> moveItem(int oldIndex, int newIndex) async {
    final currentId = state.currentItem?.id;
    final queue = [...state.queue];
    final item = queue.removeAt(oldIndex);
    queue.insert(newIndex, item);
    state = state.copyWith(
      queue: queue,
      currentIndex: currentId == null
          ? state.currentIndex
          : queue.indexWhere((entry) => entry.id == currentId),
    );
  }

  @override
  Future<void> clearQueue({bool keepCurrent = true}) async {
    final current = state.currentItem;
    state = keepCurrent && current != null
        ? state.copyWith(queue: [current], currentIndex: 0)
        : state.copyWith(queue: const [], currentIndex: -1);
  }
}
