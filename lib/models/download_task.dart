enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
  canceled,
}

class DownloadTask {
  final int bookId;
  final String title;
  final String coverUrl;
  final String savePath;

  double progress;
  int receivedBytes;
  int totalBytes;
  DownloadStatus status; // Uses the Enum here
  String? errorMessage;
  Function()? onCancel;

  DownloadTask({
    required this.bookId,
    required this.title,
    required this.coverUrl,
    required this.savePath,
    this.progress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.status = DownloadStatus.pending,
  });
}
