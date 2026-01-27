import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/book_model.dart';
import 'auth_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // Android Emulator Loopback Address
  static const String _baseUrl = "http://10.0.2.2:8000";

  /// Fetches User Books with Auto-Refresh Logic
  Future<List<BookModel>> fetchUserBooks() async {
    if (AuthService().token == null) return [];

    final url = Uri.parse('$_baseUrl/books/');

    // 1. Try Initial Request
    var response = await http.get(
      url,
      headers: {'Authorization': 'Bearer ${AuthService().token}'},
    );

    // 2. Intercept 401 (Unauthorized) -> Refresh Token
    if (response.statusCode == 401) {
      print("DEBUG: 401 detected. Trying refresh...");

      final refreshSuccess = await AuthService().tryRefreshToken();

      if (refreshSuccess) {
        // 3. Retry Request with NEW token
        response = await http.get(
          url,
          headers: {'Authorization': 'Bearer ${AuthService().token}'},
        );
      } else {
        // Refresh failed (Session expired). Stop here.
        return [];
      }
    }

    // 4. Handle Final Response
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => BookModel.fromJson(json, _baseUrl)).toList();
    } else {
      return [];
    }
  }

  // --- READER ENDPOINTS ---

  /// Fetch the Book Structure (Chapters & Sizes)
  Future<Map<String, dynamic>?> fetchManifest(String bookId) async {
    if (AuthService().token == null) return null;

    try {
      final url = Uri.parse('$_baseUrl/books/$bookId/manifest');
      var response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${AuthService().token}'},
      );

      // Auto-Refresh Logic for Manifest
      if (response.statusCode == 401) {
        if (await AuthService().tryRefreshToken()) {
          response = await http.get(
            url,
            headers: {'Authorization': 'Bearer ${AuthService().token}'},
          );
        } else {
          return null;
        }
      }

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print("Manifest Fetch Error: $e");
      return null;
    }
  }

  /// Get Last Read Progress from Cloud
  Future<Map<String, dynamic>?> getProgress(String bookId) async {
    if (AuthService().token == null) return null;

    try {
      final url = Uri.parse('$_baseUrl/books/$bookId/progress');
      var response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${AuthService().token}'},
      );

      // Auto-Refresh Logic for Progress
      if (response.statusCode == 401) {
        if (await AuthService().tryRefreshToken()) {
          response = await http.get(
            url,
            headers: {'Authorization': 'Bearer ${AuthService().token}'},
          );
        } else {
          return null;
        }
      }

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Sync Progress to Cloud
  Future<void> saveProgress(
    String bookId,
    int chapterIndex,
    double progress,
  ) async {
    if (AuthService().token == null) return;

    try {
      final url = Uri.parse('$_baseUrl/books/$bookId/progress');

      // We don't strictly need auto-refresh here since it's a background save,
      // but it's good practice. For simplicity, we fire-and-forget or just log error.
      await http.put(
        url,
        headers: {
          'Authorization': 'Bearer ${AuthService().token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'chapter_index': chapterIndex,
          'progress_percent': progress,
        }),
      );
    } catch (e) {
      print("Sync Error: $e");
    }
  }

  // Headers for Images (Used by CachedNetworkImage)
  Map<String, String> get authHeaders {
    final token = AuthService().token;
    return token != null ? {'Authorization': 'Bearer $token'} : {};
  }
}
