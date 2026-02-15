import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart'; // Ensure this is in pubspec.yaml
import 'package:mime/mime.dart'; // Ensure this is in pubspec.yaml
import 'auth_service.dart';
import '../../models/book_model.dart';

class ApiService {
  // 🟢 BASE URL
  // Use 'http://10.0.2.2:8000' for Android Emulator
  // Use 'https://xxxx.ngrok.app' for real devices
  static const String _baseUrl = "http://10.0.2.2:8000";

  static String get baseUrl => _baseUrl;

  // 🟢 HEADERS HELPER
  Map<String, String> get authHeaders {
    final headers = {
      'ngrok-skip-browser-warning': 'true',
      'Content-Type': 'application/json',
    };
    final token = AuthService().token;
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // --- 1. FETCH BOOKS (FIXED ARGUMENTS) ---
  Future<List<BookModel>> fetchUserBooks() async {
    final url = Uri.parse('$_baseUrl/books/');

    // Auto-refresh token if needed
    final response = await _authenticatedRequest(
      (headers) => http.get(url, headers: headers),
    );

    if (response.statusCode == 200) {
      final dynamic decoded = jsonDecode(response.body);

      // Handle both List [...] and Map {"books": [...]} formats safely
      if (decoded is List) {
        return decoded
            // 🟢 CORRECT: Passing '_baseUrl' as the 2nd argument
            .map(
              (json) =>
                  BookModel.fromJson(json as Map<String, dynamic>, _baseUrl),
            )
            .toList();
      } else if (decoded is Map && decoded.containsKey('books')) {
        return (decoded['books'] as List)
            // 🟢 CORRECT: Passing '_baseUrl' as the 2nd argument
            .map(
              (json) =>
                  BookModel.fromJson(json as Map<String, dynamic>, _baseUrl),
            )
            .toList();
      } else {
        print("ApiService Error: Expected List, got ${decoded.runtimeType}");
        return [];
      }
    } else {
      throw Exception('Failed to load books: ${response.statusCode}');
    }
  }

  // --- 2. UPLOAD BOOK ---
  Future<String> uploadBook(File file) async {
    final url = Uri.parse('$_baseUrl/books/upload');
    final request = http.MultipartRequest('POST', url);

    request.headers.addAll({
      'ngrok-skip-browser-warning': 'true',
      if (AuthService().token != null)
        'Authorization': 'Bearer ${AuthService().token}',
    });

    final mimeType = lookupMimeType(file.path) ?? 'application/epub+zip';
    final multipartFile = await http.MultipartFile.fromPath(
      'file',
      file.path,
      contentType: MediaType.parse(mimeType),
    );

    request.files.add(multipartFile);

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 201) {
      return "Upload successful!";
    } else if (response.statusCode == 400) {
      final data = jsonDecode(response.body);
      if (data['detail'] == "Book already exists") {
        throw "Book already exists";
      }
      throw "Invalid file";
    } else {
      throw "Upload failed: ${response.statusCode}";
    }
  }

  // --- 3. DOWNLOAD BOOK (OPTIMIZED SPEED) ---
  Future<void> downloadBook({
    required int bookId,
    required String savePath,
    required Function(int received, int total) onProgress,
  }) async {
    final url = Uri.parse('$_baseUrl/books/$bookId/download');
    final request = http.Request('GET', url);

    if (AuthService().token != null) {
      request.headers['Authorization'] = 'Bearer ${AuthService().token}';
    }
    request.headers['ngrok-skip-browser-warning'] = 'true';

    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception("Download failed: ${response.statusCode}");
    }

    final contentLength = response.contentLength ?? -1;
    int received = 0;

    final file = File(savePath);
    final sink = file.openWrite();

    // 🟢 UI THROTTLING (Prevents Lag & Increases Speed)
    // Only update UI every 1% or every 100ms
    int lastNotifiedProgress = 0;
    final stopwatch = Stopwatch()..start();

    await response.stream
        .listen(
          (chunk) {
            sink.add(chunk);
            received += chunk.length;

            if (contentLength != -1) {
              int currentProgress = ((received / contentLength) * 100).toInt();

              if (currentProgress > lastNotifiedProgress ||
                  stopwatch.elapsedMilliseconds > 100) {
                onProgress(received, contentLength);
                lastNotifiedProgress = currentProgress;
                stopwatch.reset();
              }
            }
          },
          onDone: () async {
            await sink.flush();
            await sink.close();
            onProgress(received, contentLength); // Ensure final update
          },
          onError: (e) async {
            await sink.close();
            throw e;
          },
          cancelOnError: true,
        )
        .asFuture();
  }

  // --- 4. DELETE BOOK ---
  Future<bool> deleteBook(int bookId) async {
    final url = Uri.parse('$_baseUrl/books/$bookId');
    final response = await _authenticatedRequest(
      (headers) => http.delete(url, headers: headers),
    );
    return response.statusCode == 200;
  }

  // --- 5. READER: MANIFEST ---
  Future<Map<String, dynamic>?> fetchManifest(String bookId) async {
    final url = Uri.parse('$_baseUrl/books/$bookId/manifest');
    final response = await _authenticatedRequest(
      (headers) => http.get(url, headers: headers),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  // --- 6. READER: GET PROGRESS ---
  Future<Map<String, dynamic>?> getProgress(String bookId) async {
    final url = Uri.parse('$_baseUrl/progress/$bookId');
    final response = await _authenticatedRequest(
      (headers) => http.get(url, headers: headers),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  // --- 7. READER: SAVE PROGRESS ---
  Future<void> saveProgress(
    String bookId,
    int chapterIndex,
    double progress,
  ) async {
    final url = Uri.parse('$_baseUrl/progress/$bookId');
    await _authenticatedRequest(
      (headers) => http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'chapter_index': chapterIndex,
          'progress_percent': progress,
        }),
      ),
    );
  }

  // 🟢 AUTH HELPER (Auto Token Refresh)
  Future<http.Response> _authenticatedRequest(
    Future<http.Response> Function(Map<String, String>) request,
  ) async {
    var response = await request(authHeaders);

    if (response.statusCode == 401) {
      print("ApiService: Token expired, refreshing...");
      final success = await AuthService().tryRefreshToken();
      if (success) {
        print("ApiService: Token refreshed, retrying request...");
        response = await request(authHeaders);
      }
    }

    return response;
  }
}
