enum TranscriptionQueueItemStatus {
  queued,
  running,
  paused,
  completed,
  failed,
}

enum TranscriptionQueuePauseReason {
  manual,
  environment,
}

class TranscriptionQueueItem {
  final String id;
  final String sourcePath;
  final String projectName;
  final String? projectId;
  final TranscriptionQueueItemStatus status;
  final double progress;
  final String message;
  final String? error;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TranscriptionQueueItem({
    required this.id,
    required this.sourcePath,
    required this.projectName,
    this.projectId,
    this.status = TranscriptionQueueItemStatus.queued,
    this.progress = 0,
    this.message = '等待识别',
    this.error,
    required this.createdAt,
    required this.updatedAt,
  });

  TranscriptionQueueItem copyWith({
    String? projectId,
    TranscriptionQueueItemStatus? status,
    double? progress,
    String? message,
    String? error,
    bool clearError = false,
    DateTime? updatedAt,
  }) {
    return TranscriptionQueueItem(
      id: id,
      sourcePath: sourcePath,
      projectName: projectName,
      projectId: projectId ?? this.projectId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      error: clearError ? null : error ?? this.error,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourcePath': sourcePath,
        'projectName': projectName,
        'projectId': projectId,
        'status': status.name,
        'progress': progress,
        'message': message,
        'error': error,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory TranscriptionQueueItem.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String?;
    return TranscriptionQueueItem(
      id: json['id'] as String,
      sourcePath: json['sourcePath'] as String,
      projectName: json['projectName'] as String,
      projectId: json['projectId'] as String?,
      status: TranscriptionQueueItemStatus.values.asNameMap()[statusName] ??
          TranscriptionQueueItemStatus.queued,
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      message: json['message'] as String? ?? '等待识别',
      error: json['error'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

class TranscriptionQueueSnapshot {
  final List<TranscriptionQueueItem> items;
  final bool isPaused;
  final bool isProcessing;
  final TranscriptionQueuePauseReason? pauseReason;
  final String? pauseMessage;

  const TranscriptionQueueSnapshot({
    required this.items,
    required this.isPaused,
    required this.isProcessing,
    this.pauseReason,
    this.pauseMessage,
  });

  bool get isEnvironmentBlocked =>
      isPaused && pauseReason == TranscriptionQueuePauseReason.environment;

  int get queuedCount => items
      .where((item) => item.status == TranscriptionQueueItemStatus.queued)
      .length;

  int get completedCount => items
      .where((item) => item.status == TranscriptionQueueItemStatus.completed)
      .length;

  int get failedCount => items
      .where((item) => item.status == TranscriptionQueueItemStatus.failed)
      .length;
}
