enum MediaTransferDirection { downloadFromDesktop, uploadToDesktop }

enum MediaTransferItemStatus { queued, transferring, completed, failed }

class MediaTransferItemProgress {
  final String id;
  final String title;
  final MediaTransferDirection direction;
  final MediaTransferItemStatus status;
  final int bytesTransferred;
  final int? totalBytes;
  final String? destinationPath;
  final String? error;

  const MediaTransferItemProgress({
    required this.id,
    required this.title,
    required this.direction,
    required this.status,
    this.bytesTransferred = 0,
    this.totalBytes,
    this.destinationPath,
    this.error,
  });

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (bytesTransferred / total).clamp(0.0, 1.0).toDouble();
  }
}

class MediaTransferItemResult {
  final String id;
  final String title;
  final MediaTransferDirection direction;
  final bool succeeded;
  final String? destinationPath;
  final String? error;

  const MediaTransferItemResult({
    required this.id,
    required this.title,
    required this.direction,
    required this.succeeded,
    this.destinationPath,
    this.error,
  });
}

class MediaTransferBatchResult {
  final List<MediaTransferItemResult> items;

  const MediaTransferBatchResult(this.items);

  List<MediaTransferItemResult> get completed =>
      items.where((item) => item.succeeded).toList(growable: false);
  List<MediaTransferItemResult> get failed =>
      items.where((item) => !item.succeeded).toList(growable: false);
  bool get hasFailures => failed.isNotEmpty;
}
