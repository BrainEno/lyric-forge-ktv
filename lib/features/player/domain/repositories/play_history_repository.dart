import '../models/play_history.dart';

/// 最大历史记录数量
const int maxHistoryCount = 50;

/// 播放历史存储接口
abstract class PlayHistoryRepository {
  /// 保存播放历史
  Future<void> savePlayHistory(PlayHistory history);

  /// 获取最近播放历史
  Future<List<PlayHistory>> getRecentPlayHistory({int limit = 10});

  /// 清空播放历史
  Future<void> clearPlayHistory();

  /// 删除指定播放历史
  Future<void> removePlayHistory(String id);

  /// 根据 ID 获取播放历史
  Future<PlayHistory?> getPlayHistoryById(String id);
}
