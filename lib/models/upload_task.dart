enum UploadStatus { pending, uploading, completed, failed, canceled }

class UploadTask {
  final String id;
  final String filePath;
  final String title;

  double progress;
  UploadStatus status;
  String? errorMessage;

  void Function()? onCancel;

  UploadTask({
    required this.id,
    required this.filePath,
    required this.title,
    this.progress = 0.0,
    this.status = UploadStatus.pending,
  });
}
