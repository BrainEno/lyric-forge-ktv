import '../../../project/domain/models/lyric_document.dart';

/// 参考歌词对齐写入的单槽备份键；恢复成功后被消耗，不允许重复恢复旧快照。
const String kReferenceAlignmentBackupKey = 'referenceAlignmentBackup';

/// 恢复成功时写入的溯源键。
const String kReferenceAlignmentRestoreKey = 'referenceAlignmentRestore';

/// 备份不可用的具体原因，供入口展示与提示区分。
enum ReferenceAlignmentBackupIssue {
  /// 备份键不存在。
  missing,

  /// 备份结构类型错误（字段缺失或类型不符）。
  invalidShape,

  /// 备份文档 JSON 已损坏，无法构造 LyricDocument。
  corruptDocument,

  /// 文档实际行数与记录的 lineCount 不一致（快照缺行/多行）。
  lineCountMismatch,
}

/// 恢复确认对话框需要展示的备份摘要。
class ReferenceAlignmentBackupSummary {
  final DateTime createdAt;
  final String reason;
  final String source;
  final String? sourcePath;
  final String format;
  final int lineCount;

  const ReferenceAlignmentBackupSummary({
    required this.createdAt,
    required this.reason,
    required this.source,
    this.sourcePath,
    required this.format,
    required this.lineCount,
  });
}

/// [ReferenceAlignmentRestoreService.probeBackup] 的结果。
sealed class ReferenceAlignmentBackupProbe {
  const ReferenceAlignmentBackupProbe();
}

final class ReferenceAlignmentBackupAvailable
    extends ReferenceAlignmentBackupProbe {
  final ReferenceAlignmentBackupSummary summary;

  const ReferenceAlignmentBackupAvailable({required this.summary});
}

final class ReferenceAlignmentBackupUnavailable
    extends ReferenceAlignmentBackupProbe {
  final ReferenceAlignmentBackupIssue issue;

  const ReferenceAlignmentBackupUnavailable({required this.issue});
}

/// [ReferenceAlignmentRestoreService.restore] 的结果。
sealed class ReferenceAlignmentRestoreResult {
  const ReferenceAlignmentRestoreResult();
}

final class ReferenceAlignmentRestoreSuccess
    extends ReferenceAlignmentRestoreResult {
  final LyricDocument document;
  final ReferenceAlignmentBackupSummary summary;

  const ReferenceAlignmentRestoreSuccess({
    required this.document,
    required this.summary,
  });
}

final class ReferenceAlignmentRestoreFailure
    extends ReferenceAlignmentRestoreResult {
  final ReferenceAlignmentBackupIssue issue;

  const ReferenceAlignmentRestoreFailure({required this.issue});
}

/// 解析、校验并恢复 `metadata['referenceAlignmentBackup']` 单槽快照的纯 Dart 服务。
///
/// 恢复只生成新文档，不修改入参、不落盘：是否保存由调用方显式决定。
/// 成功后新文档写入 `referenceAlignmentRestore` 溯源并移除备份键（单槽语义），
/// 备份文档自带的旧 `referenceAlignment` 溯源原样保留。
class ReferenceAlignmentRestoreService {
  const ReferenceAlignmentRestoreService();

  /// 校验备份是否存在且可解析；失败时返回可区分的原因。
  ReferenceAlignmentBackupProbe probeBackup(LyricDocument document) {
    final parsed = _parseBackup(document.metadata);
    final issue = parsed.issue;
    if (issue != null) return ReferenceAlignmentBackupUnavailable(issue: issue);
    return ReferenceAlignmentBackupAvailable(summary: parsed.summary!);
  }

  /// 用备份快照生成恢复后的文档；任何校验失败都不产出新文档。
  ReferenceAlignmentRestoreResult restore(
    LyricDocument document, {
    DateTime? now,
  }) {
    final parsed = _parseBackup(document.metadata);
    final issue = parsed.issue;
    if (issue != null) return ReferenceAlignmentRestoreFailure(issue: issue);

    final summary = parsed.summary!;
    final backupDocument = parsed.document!;

    final metadata = Map<String, dynamic>.from(backupDocument.metadata)
      ..remove(kReferenceAlignmentBackupKey);
    metadata[kReferenceAlignmentRestoreKey] = <String, dynamic>{
      'source': 'reference-alignment-restore',
      'restoredAt': (now ?? DateTime.now()).toIso8601String(),
      'backupCreatedAt': summary.createdAt.toIso8601String(),
      'backupReason': summary.reason,
      'backupLineCount': summary.lineCount,
      'restoredLineCount': backupDocument.lines.length,
    };

    return ReferenceAlignmentRestoreSuccess(
      document: LyricDocument(
        language: backupDocument.language,
        lines: backupDocument.lines,
        globalOffset: backupDocument.globalOffset,
        metadata: metadata,
      ),
      summary: summary,
    );
  }

  ({
    ReferenceAlignmentBackupIssue? issue,
    ReferenceAlignmentBackupSummary? summary,
    LyricDocument? document,
  })
  _parseBackup(Map<String, dynamic> metadata) {
    final raw = metadata[kReferenceAlignmentBackupKey];
    if (raw == null) {
      return (
        issue: ReferenceAlignmentBackupIssue.missing,
        summary: null,
        document: null,
      );
    }
    if (raw is! Map) {
      return (
        issue: ReferenceAlignmentBackupIssue.invalidShape,
        summary: null,
        document: null,
      );
    }

    final Map<String, dynamic> backup;
    try {
      backup = Map<String, dynamic>.from(raw);
    } catch (_) {
      return (
        issue: ReferenceAlignmentBackupIssue.invalidShape,
        summary: null,
        document: null,
      );
    }

    final createdAt = backup['createdAt'];
    final reason = backup['reason'];
    final source = backup['source'];
    final sourcePath = backup['sourcePath'];
    final format = backup['format'];
    final lineCount = backup['lineCount'];
    final documentRaw = backup['document'];

    final shapeLooksValid =
        createdAt is String &&
        DateTime.tryParse(createdAt) != null &&
        reason is String &&
        source is String &&
        format is String &&
        (sourcePath == null || sourcePath is String) &&
        lineCount is int &&
        lineCount >= 0 &&
        documentRaw is Map;
    if (!shapeLooksValid) {
      return (
        issue: ReferenceAlignmentBackupIssue.invalidShape,
        summary: null,
        document: null,
      );
    }

    final LyricDocument backupDocument;
    try {
      backupDocument = LyricDocument.fromJson(
        Map<String, dynamic>.from(documentRaw),
      );
    } catch (_) {
      return (
        issue: ReferenceAlignmentBackupIssue.corruptDocument,
        summary: null,
        document: null,
      );
    }

    if (backupDocument.lines.length != lineCount) {
      return (
        issue: ReferenceAlignmentBackupIssue.lineCountMismatch,
        summary: null,
        document: null,
      );
    }

    return (
      issue: null,
      summary: ReferenceAlignmentBackupSummary(
        createdAt: DateTime.parse(createdAt),
        reason: reason,
        source: source,
        sourcePath: sourcePath as String?,
        format: format,
        lineCount: lineCount,
      ),
      document: backupDocument,
    );
  }
}
