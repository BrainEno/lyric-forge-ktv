import '../../domain/models/play_history.dart';
import '../../domain/repositories/play_history_repository.dart';

/// 内存实现的播放历史存储
/// 临时方案，后续可替换为持久化存储
class MemoryPlayHistoryRepository implements PlayHistoryRepository {
  final List<PlayHistory> _histories = [];

  @override
  Future<void> savePlayHistory(PlayHistory history) async {
    // 移除重复项（同文件路径）
    _histories.removeWhere((h) => h.filePath == history.filePath);
    // 添加到开头
    _histories.insert(0, history);
    // 限制最大数量
    if (_histories.length > maxHistoryCount) {
      _histories.removeRange(maxHistoryCount, _histories.length);
    }
  }

  @override
  Future<List<PlayHistory>> getRecentPlayHistory({int limit = 10}) async {
    return _histories.take(limit).toList();
  }

  @override
  Future<void> clearPlayHistory() async {
    _histories.clear();
  }

  @override
  Future<void> removePlayHistory(String id) async {
    _histories.removeWhere((h) => h.id == id);
  }

  @override
  Future<PlayHistory?> getPlayHistoryById(String id) async {
    try {
      return _histories.firstWhere((h) => h.id == id);
    } catch (_) {
      return null;
    }
  }
}
