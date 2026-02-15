import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../../models/upload_task.dart';
import 'api_service.dart';
import 'auth_service.dart';

class UploadService extends ChangeNotifier {
  static final UploadService _instance = UploadService._internal();
  factory UploadService() => _instance;
  UploadService._internal();

  final List<UploadTask> _tasks = [];
  List<UploadTask> get tasks => _tasks;

  bool _isUploading = false;
  VoidCallback? onUploadCompleted;

  List<String> _onlineBookTitles = [];

  void updateOnlineBooksCache(List<dynamic> books) {
    _onlineBookTitles = books
        .map((b) => _normalize(b.title.toString()))
        .toList();
  }

  String _normalize(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  bool _isDuplicate(String titleToCheck) {
    final cleanTitle = _normalize(titleToCheck);
    if (cleanTitle.isEmpty) return false;

    for (String onlineTitle in _onlineBookTitles) {
      if (cleanTitle == onlineTitle) return true;
      if (cleanTitle.length > 4 && onlineTitle.length > 4) {
        if (cleanTitle.contains(onlineTitle) ||
            onlineTitle.contains(cleanTitle)) {
          return true;
        }
      }
    }
    return false;
  }

  void removeTask(String id) {
    _tasks.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  void addToQueue(File file, {String? knownTitle}) {
    // 🟢 CLEANUP FIX: Only remove finished tasks if we are re-uploading
    _tasks.removeWhere(
      (t) => t.id == file.path && t.status == UploadStatus.completed,
    );

    final String id = file.path;
    if (_tasks.any((t) => t.id == id)) return;

    final displayTitle = knownTitle ?? p.basename(file.path);

    final task = UploadTask(id: id, filePath: file.path, title: displayTitle);

    if (knownTitle != null) {
      if (_isDuplicate(knownTitle)) {
        task.status = UploadStatus.failed;
        task.errorMessage = "Already in cloud";
        _tasks.add(task);
        notifyListeners();
        return;
      }
    } else {
      final filename = p.basenameWithoutExtension(file.path);
      if (_isDuplicate(filename)) {
        task.status = UploadStatus.failed;
        task.errorMessage = "Already in cloud";
        _tasks.add(task);
        notifyListeners();
        return;
      }
    }

    _tasks.add(task);
    notifyListeners();
    _processQueue();
  }

  void _processQueue() async {
    if (_isUploading) return;
    try {
      final task = _tasks.firstWhere((t) => t.status == UploadStatus.pending);
      _startUpload(task);
    } catch (e) {
      // Queue empty
    }
  }

  Future<void> _startUpload(UploadTask task) async {
    _isUploading = true;
    task.status = UploadStatus.uploading;
    notifyListeners();

    bool retryMode = false;

    try {
      while (true) {
        final file = File(task.filePath);
        if (!file.existsSync()) throw "File not found on device";

        final filenameSafe = p.basenameWithoutExtension(file.path);
        // Note: We skip duplicate check here if we want to allow re-uploads,
        // but keeping it safe is fine.
        if (_isDuplicate(filenameSafe))
          throw "Book already exists (Name Match)";

        final totalBytes = await file.length();

        // 🟢 FIX: Correct Endpoint is /books/ (POST)
        final url = Uri.parse('${ApiService.baseUrl}/books/');

        final request = http.MultipartRequest('POST', url);
        request.headers.addAll(ApiService().authHeaders);

        final byteStream = file.openRead();
        int bytesUploaded = 0;
        final stopwatch = Stopwatch()..start();

        final stream = http.ByteStream(
          byteStream.transform(
            StreamTransformer.fromHandlers(
              handleData: (data, sink) async {
                bytesUploaded += data.length;
                sink.add(data);

                // 🟢 UI THROTTLE: Update every 500ms max
                if (stopwatch.elapsedMilliseconds > 500) {
                  task.progress = bytesUploaded / totalBytes;
                  notifyListeners();
                  stopwatch.reset();
                  await Future.delayed(Duration.zero);
                }
              },
            ),
          ),
        );

        final mimeType = lookupMimeType(file.path) ?? 'application/epub+zip';
        final multipartFile = http.MultipartFile(
          'file',
          stream,
          totalBytes,
          filename: p.basename(task.filePath),
          contentType: MediaType.parse(mimeType),
        );

        request.files.add(multipartFile);

        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);

        // 🟢 RETRY LOGIC (401 Unauthorized)
        if (response.statusCode == 401 && !retryMode) {
          print("UploadService: Token expired. Refreshing...");
          final success = await AuthService().tryRefreshToken();
          if (success) {
            retryMode = true;
            continue; // Loop again to retry upload
          }
        }

        // 🟢 STATUS CODE FIX: Accept 200 and 201
        if (response.statusCode == 200 || response.statusCode == 201) {
          task.status = UploadStatus.completed;
          task.progress = 1.0;
          notifyListeners();

          onUploadCompleted?.call();
          break; // Exit loop
        } else if (response.statusCode == 409) {
          throw "Book already exists";
        } else if (response.statusCode == 400) {
          // Parse error detail from server if possible
          try {
            // If server returns {"detail": "Book already exists"}
            if (response.body.contains("already exists")) {
              throw "Book already exists";
            }
          } catch (_) {}
          throw "Invalid File or Bad Request";
        } else if (response.statusCode == 405) {
          throw "Server Error (405): Method Not Allowed";
        } else {
          throw "Upload Failed: ${response.statusCode}";
        }
      }
    } catch (e) {
      task.status = UploadStatus.failed;
      task.errorMessage = e.toString().replaceAll("Exception:", "").trim();

      if (task.errorMessage!.toLowerCase().contains("exists")) {
        task.errorMessage = "Already in cloud";
      }

      notifyListeners();
    } finally {
      _isUploading = false;
      _processQueue();
    }
  }
}
