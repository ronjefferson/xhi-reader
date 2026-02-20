import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import '../../models/book_model.dart';

class ApiService {
  static const String _baseUrl = "http://10.0.2.2:8000";
  static String get baseUrl => _baseUrl;

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

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

  // --- 1. FETCH BOOKS (GET /books/) ---
  Future<List<BookModel>> fetchUserBooks() async {
    final url = Uri.parse('$_baseUrl/books/');
    final response = await _authenticatedRequest(
      (headers) => http.get(url, headers: headers),
    );

    if (response.statusCode == 200) {
      final dynamic decoded = jsonDecode(response.body);

      // Handle List [...]
      if (decoded is List) {
        return decoded
            .map(
              (json) =>
                  BookModel.fromJson(json as Map<String, dynamic>, _baseUrl),
            )
            .toList();
      }
      // Handle {"books": [...]}
      else if (decoded is Map && decoded.containsKey('books')) {
        return (decoded['books'] as List)
            .map(
              (json) =>
                  BookModel.fromJson(json as Map<String, dynamic>, _baseUrl),
            )
            .toList();
      } else {
        return [];
      }
    } else {
      throw Exception('Failed to load books: ${response.statusCode}');
    }
  }

  // --- 2. DELETE BOOK (DELETE /books/{id}) ---
  Future<bool> deleteBook(int bookId) async {
    final url = Uri.parse('$_baseUrl/books/$bookId');
    final response = await _authenticatedRequest(
      (headers) => http.delete(url, headers: headers),
    );

    // 🟢 IMPROVED: Accept both 200 and 204 (No Content)
    return response.statusCode == 200 || response.statusCode == 204;
  }

  // --- 3. MANIFEST (GET /books/{id}/manifest) ---
  Future<Map<String, dynamic>?> fetchManifest(int bookId) async {
    final url = Uri.parse('$_baseUrl/books/$bookId/manifest');
    final response = await _authenticatedRequest(
      (headers) => http.get(url, headers: headers),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  // --- 4. GET PROGRESS (GET /books/{id}/progress) ---
  Future<Map<String, dynamic>?> getReadingProgress(int bookId) async {
    final url = Uri.parse('$_baseUrl/books/$bookId/progress');
    final response = await _authenticatedRequest(
      (headers) => http.get(url, headers: headers),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else if (response.statusCode == 404) {
      return null; // No progress saved yet
    }
    return null;
  }

  // --- 5. UPDATE PROGRESS (PUT /books/{id}/progress) ---
  Future<void> updateReadingProgress(
    int bookId,
    int chapterIndex,
    double progressPercent,
  ) async {
    final url = Uri.parse('$_baseUrl/books/$bookId/progress');

    // 🟢 PUT Method (Matches API Docs)
    await _authenticatedRequest(
      (headers) => http.put(
        url,
        headers: headers,
        body: jsonEncode({
          'chapter_index': chapterIndex,
          'progress_percent': progressPercent,
        }),
      ),
    );
  }

  // 🟢 AUTH HELPER
  Future<http.Response> _authenticatedRequest(
    Future<http.Response> Function(Map<String, String>) request,
  ) async {
    var response = await request(authHeaders);

    if (response.statusCode == 401) {
      print("ApiService: Token expired, refreshing...");
      final success = await AuthService().tryRefreshToken();
      if (success) {
        response = await request(authHeaders);
      }
    }
    return response;
  }
}
