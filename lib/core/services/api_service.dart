import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import '../../models/book_model.dart';
import 'auth_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // 🟢 REPLACE THIS WITH YOUR CURRENT NGROK URL
  static const String _baseUrl = "http://10.0.2.2:8000";

  // Expose URL for AuthService to use
  static String get baseUrl => _baseUrl;

  final Dio _dio = Dio();

  Map<String, String> get _authHeaders {
    return {
      'Authorization': 'Bearer ${AuthService().token}',
      // 🟢 REQUIRED: Bypasses Ngrok warning page for API calls
      'ngrok-skip-browser-warning': 'true',
    };
  }

  /// Fetches User Books
  Future<List<BookModel>> fetchUserBooks() async {
    if (AuthService().token == null) return [];

    final url = Uri.parse('$_baseUrl/books/');
    var response = await http.get(url, headers: _authHeaders);

    if (response.statusCode == 401) {
      final refreshSuccess = await AuthService().tryRefreshToken();
      if (refreshSuccess) {
        response = await http.get(url, headers: _authHeaders);
      } else {
        return [];
      }
    }

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => BookModel.fromJson(json, _baseUrl)).toList();
    } else {
      return [];
    }
  }

  /// Upload Book
  Future<String> uploadBook(File file) async {
    final url = Uri.parse('$_baseUrl/books/');

    final request = http.MultipartRequest('POST', url);
    request.headers.addAll(_authHeaders);
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return "Upload successful!";
    } else if (response.statusCode == 400) {
      final data = jsonDecode(response.body);
      throw data['detail'] ?? "Upload failed";
    } else if (response.statusCode == 413) {
      throw "File is too large (Limit: 1GB)";
    } else if (response.statusCode == 401) {
      throw "Session expired. Please login again.";
    } else {
      throw "Server error: ${response.statusCode}";
    }
  }

  /// Download Book (Streaming)
  Future<void> downloadBook({
    required int bookId,
    required String savePath,
    required Function(int received, int total) onProgress,
  }) async {
    final url = '$_baseUrl/books/$bookId/download';

    try {
      await _dio.download(
        url,
        savePath,
        options: Options(
          headers: _authHeaders,
          responseType: ResponseType.stream,
        ),
        onReceiveProgress: onProgress,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw "Session expired";
      } else if (e.response?.statusCode == 404) {
        throw "File missing from server";
      }
      throw "Download failed: ${e.message}";
    }
  }

  /// Delete Book
  Future<bool> deleteBook(int bookId) async {
    final url = Uri.parse('$_baseUrl/books/$bookId');

    try {
      var response = await http.delete(url, headers: _authHeaders);

      if (response.statusCode == 401) {
        final refreshed = await AuthService().tryRefreshToken();
        if (refreshed) {
          response = await http.delete(url, headers: _authHeaders);
        } else {
          return false;
        }
      }

      if (response.statusCode == 200 || response.statusCode == 404) {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // --- READER ENDPOINTS ---
  Future<Map<String, dynamic>?> fetchManifest(String bookId) async {
    if (AuthService().token == null) return null;
    try {
      final url = Uri.parse('$_baseUrl/books/$bookId/manifest');
      var response = await http.get(url, headers: _authHeaders);

      if (response.statusCode == 401 && await AuthService().tryRefreshToken()) {
        response = await http.get(url, headers: _authHeaders);
      }
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getProgress(String bookId) async {
    if (AuthService().token == null) return null;
    try {
      final url = Uri.parse('$_baseUrl/books/$bookId/progress');
      var response = await http.get(url, headers: _authHeaders);
      if (response.statusCode == 401 && await AuthService().tryRefreshToken()) {
        response = await http.get(url, headers: _authHeaders);
      }
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> saveProgress(
    String bookId,
    int chapterIndex,
    double progress,
  ) async {
    if (AuthService().token == null) return;
    try {
      final url = Uri.parse('$_baseUrl/books/$bookId/progress');
      await http.put(
        url,
        headers: {..._authHeaders, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'chapter_index': chapterIndex,
          'progress_percent': progress,
        }),
      );
    } catch (e) {
      print("Sync Error: $e");
    }
  }

  Map<String, String> get authHeaders => _authHeaders;
}
