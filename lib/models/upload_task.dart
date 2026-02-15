enum UploadStatus { pending, uploading, completed, failed, canceled }

class UploadTask {
  final String id; // Unique ID (usually file path)
  final String filePath;
  final String title;

  double progress; // 0.0 to 1.0
  UploadStatus status;
  String? errorMessage;

  // We need a way to cancel the upload
  void Function()? onCancel;

  UploadTask({
    required this.id,
    required this.filePath,
    required this.title,
    this.progress = 0.0,
    this.status = UploadStatus.pending,
  });
}
