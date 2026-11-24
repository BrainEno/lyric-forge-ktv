import 'getting_started.dart';

/// Saves [GettingStartedPreferences] between launches (D-070, D-071).
abstract class GettingStartedStore {
  /// The saved preferences; null when nothing was saved or it is unreadable.
  Future<GettingStartedPreferences?> load();

  Future<void> save(GettingStartedPreferences preferences);
}

/// Keeps the preferences in memory: before bootstrap and in tests.
class MemoryGettingStartedStore implements GettingStartedStore {
  GettingStartedPreferences? saved;

  MemoryGettingStartedStore([this.saved]);

  @override
  Future<GettingStartedPreferences?> load() async => saved;

  @override
  Future<void> save(GettingStartedPreferences preferences) async {
    saved = preferences;
  }
}

/// 设置 › 开始使用指南 › 在首页重新显示: puts the card back, keeping what
/// the user already did.
Future<void> showGettingStartedAgain(GettingStartedStore store) async {
  final current = await store.load() ?? const GettingStartedPreferences();
  await store.save(
    current.copyWith(visibility: GettingStartedVisibility.active),
  );
}
