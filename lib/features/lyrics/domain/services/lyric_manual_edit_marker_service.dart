import 'package:uuid/uuid.dart';

import '../../../project/domain/models/lyric_document.dart';

/// 为编辑器"手工编辑保护"提供稳定行标识的分配与持久化。
///
/// 会话内以 lineId 记录哪些行被手动改过：插入、删除、参考对齐等结构变化后
/// 标识不随索引漂移；保存时把标识写入文档 metadata，重开工程后恢复，
/// 使保护标记不再局限于单次编辑器会话。
class LyricManualEditMarkerService {
  const LyricManualEditMarkerService();

  /// 手工编辑标记在文档 metadata 中的键。
  static const String manuallyEditedLineIdsKey = 'manuallyEditedLineIds';

  static const Uuid _uuid = Uuid();

  /// 为缺少标识的行分配稳定 id；已有 id 保持不变。幂等。
  LyricDocument assignMissingLineIds(LyricDocument document) {
    var changed = false;
    final lines = <LyricLine>[];
    for (final line in document.lines) {
      if (line.id == null) {
        changed = true;
        lines.add(line.copyWith(id: _uuid.v4()));
      } else {
        lines.add(line);
      }
    }
    if (!changed) return document;
    return document.copyWith(lines: lines);
  }

  /// 把会话内的手工编辑标记写入文档 metadata。
  /// 仅保留当前行集中仍存在的 id，结构变化后失效的标记不会被持久化。
  Map<String, dynamic> persist(LyricDocument document, Set<String> markerIds) {
    final stored = prune(document, markerIds).toList()..sort();
    return Map<String, dynamic>.from(document.metadata)
      ..[manuallyEditedLineIdsKey] = stored;
  }

  /// 从文档 metadata 恢复手工编辑标记，过滤掉行集中已不存在的 id。
  Set<String> restore(LyricDocument document) {
    final raw = document.metadata[manuallyEditedLineIdsKey];
    if (raw is! List) return <String>{};
    return prune(document, {
      for (final value in raw)
        if (value is String) value,
    });
  }

  /// 只保留标记中仍存在于当前行集的 id（清理失效标记）。
  Set<String> prune(LyricDocument document, Set<String> markerIds) {
    if (markerIds.isEmpty) return <String>{};
    final existing = _existingLineIds(document);
    return markerIds.where(existing.contains).toSet();
  }

  /// 派生当前受保护（手工编辑过）的行索引，供逐行确认与批量应用使用。
  /// 行序变化后由稳定标识重新定位，不依赖旧索引。
  Set<int> protectedIndices(LyricDocument document, Set<String> markerIds) {
    if (markerIds.isEmpty) return <int>{};
    final indices = <int>{};
    for (var index = 0; index < document.lines.length; index++) {
      final id = document.lines[index].id;
      if (id != null && markerIds.contains(id)) {
        indices.add(index);
      }
    }
    return indices;
  }

  Set<String> _existingLineIds(LyricDocument document) => {
    for (final line in document.lines)
      if (line.id != null) line.id!,
  };
}
