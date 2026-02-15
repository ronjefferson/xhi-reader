import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../models/download_task.dart';
import 'api_service.dart';
import 'auth_service.dart';

class DownloadService extends ChangeNotifier {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;

  DownloadService._internal();

  final List<DownloadTask> _tasks = [];
  List<DownloadTask> get tasks => _tasks;

  final int _maxConcurrent = 1;

  VoidCallback? onBookDownloaded;

  // --- PUBLIC ACTIONS ---

  void addToQueue(int bookId, String title, String coverUrl, String savePath) {
    // 🟢 FIX: Only remove an old entry for THIS specific book (if completed/failed).
    // Do NOT wipe the entire history of other downloads.
    _tasks.removeWhere(
      (t) =>
          t.bookId == bookId &&
          (t.status == DownloadStatus.completed ||
              t.status == DownloadStatus.failed),
    );

    // Prevent duplicate active downloads
    if (_tasks.any(
      (t) =>
          t.bookId == bookId &&
          (t.status == DownloadStatus.pending ||
              t.status == DownloadStatus.downloading),
    )) {
      return;
    }

    final task = DownloadTask(
      bookId: bookId,
      title: title,
      coverUrl: coverUrl,
      savePath: savePath,
    );

    _tasks.add(task);
    notifyListeners();
    _processQueue();
  }

  void cancelTask(DownloadTask task) {
    if (task.status == DownloadStatus.downloading) {
      task.onCancel?.call();
    }
    _cleanupFile(task.savePath);
    _tasks.remove(task);
    notifyListeners();
    _processQueue();
  }

  void removeTask(int bookId) {
    _tasks.removeWhere((t) => t.bookId == bookId);
    notifyListeners();
  }

  void pauseTask(DownloadTask task) {
    if (task.status == DownloadStatus.downloading) {
      task.onCancel?.call();
      task.status = DownloadStatus.paused;
      notifyListeners();
      _processQueue();
    }
  }

  void resumeTask(DownloadTask task) {
    if (task.status == DownloadStatus.paused ||
        task.status == DownloadStatus.failed) {
      task.status = DownloadStatus.pending;
      notifyListeners();
      _processQueue();
    }
  }

  void _cleanupFile(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (e) {
      /* ignore */
    }
  }

  // --- INTERNAL ENGINE ---

  void _processQueue() {
    int activeCount = _tasks
        .where((t) => t.status == DownloadStatus.downloading)
        .length;
    if (activeCount < _maxConcurrent) {
      try {
        final nextTask = _tasks.firstWhere(
          (t) => t.status == DownloadStatus.pending,
        );
        _startDownload(nextTask);
      } catch (e) {
        /* Queue Empty */
      }
    }
  }

  Future<void> _startDownload(DownloadTask task) async {
    task.status = DownloadStatus.downloading;
    notifyListeners();

    final client = http.Client();
    task.onCancel = () => client.close();

    bool retryMode = false;

    try {
      while (true) {
        final url = Uri.parse(
          '${ApiService.baseUrl}/books/${task.bookId}/download',
        );

        final request = http.Request('GET', url);
        request.headers.addAll(ApiService().authHeaders);

        final response = await client.send(request);

        if (response.statusCode == 401 && !retryMode) {
          print("DownloadService: Token expired. Refreshing...");
          await response.stream.drain();

          final success = await AuthService().tryRefreshToken();
          if (success) {
            retryMode = true;
            continue;
          }
        }

        if (response.statusCode != 200) {
          throw "Server error: ${response.statusCode}";
        }

        task.totalBytes = response.contentLength ?? -1;
        task.receivedBytes = 0;
        task.progress = 0.0;

        final file = File(task.savePath);
        final sink = file.openWrite();

        final stopwatch = Stopwatch()..start();

        await for (var chunk in response.stream) {
          sink.add(chunk);
          task.receivedBytes += chunk.length;

          if (stopwatch.elapsedMilliseconds > 1500) {
            if (task.totalBytes != -1) {
              task.progress = task.receivedBytes / task.totalBytes;
            }
            notifyListeners();
            stopwatch.reset();
            await Future.delayed(const Duration(milliseconds: 50));
          }
        }

        await sink.flush();
        await sink.close();
        client.close();

        task.progress = 1.0;
        task.status = DownloadStatus.completed;
        notifyListeners();

        if (onBookDownloaded != null) onBookDownloaded!();

        break;
      }
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.errorMessage = "Download Error";
      notifyListeners();
    } finally {
      _processQueue();
    }
  }
}
