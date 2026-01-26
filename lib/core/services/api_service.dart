import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/book_model.dart';
import 'auth_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static const String _baseUrl = "http://10.0.2.2:8000";

  /// Fetches User Books with Auto-Refresh Logic
  Future<List<BookModel>> fetchUserBooks() async {
    if (AuthService().token == null) return [];

    final url = Uri.parse('$_baseUrl/books/');

    // 1. Try Request
    var response = await http.get(
      url,
      headers: {'Authorization': 'Bearer ${AuthService().token}'},
    );

    // 2. Intercept 401 (Unauthorized)
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

  // Headers for Images (Note: Images usually retry automatically or fail visibly)
  Map<String, String> get authHeaders {
    final token = AuthService().token;
    return token != null ? {'Authorization': 'Bearer $token'} : {};
  }
}
