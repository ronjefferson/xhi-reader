import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final StreamController<bool> _sessionExpiredController =
      StreamController<bool>.broadcast();
  Stream<bool> get sessionExpiredStream => _sessionExpiredController.stream;

  String? _token;
  String? _refreshToken;
  String? _username;

  String? get token => _token;
  String? get username => _username;
  bool get isLoggedIn => _token != null;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('access_token');
    _refreshToken = prefs.getString('refresh_token');
    _username = prefs.getString('username');
  }

  /// --- REGISTER (New) ---
  Future<String?> register(String email, String password) async {
    final url = Uri.parse('${ApiService.baseUrl}/register');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json', // 🟢 REQUIRED by backend
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        return null; // Success (No error message)
      } else {
        // Return the error message from the backend (e.g., "Email already registered")
        final data = jsonDecode(response.body);
        return data['detail'] ?? "Registration failed";
      }
    } catch (e) {
      return "Connection error: $e";
    }
  }

  /// --- LOGIN ---
  Future<bool> login(String username, String password) async {
    final url = Uri.parse('${ApiService.baseUrl}/token');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'ngrok-skip-browser-warning': 'true',
        },
        body: {'username': username, 'password': password},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['access_token'];
        _refreshToken = data['refresh_token'];
        _username = username;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', _token!);
        await prefs.setString('refresh_token', _refreshToken!);
        await prefs.setString('username', _username!);

        return true;
      } else {
        print("Login Failed: ${response.statusCode} ${response.body}");
        return false;
      }
    } catch (e) {
      print("Login Connection Error: $e");
      return false;
    }
  }

  /// --- LOGOUT ---
  Future<void> logout() async {
    _token = null;
    _refreshToken = null;
    _username = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('username');
  }

  /// --- REFRESH TOKEN ---
  Future<bool> tryRefreshToken() async {
    if (_refreshToken == null) {
      _sessionExpiredController.add(true);
      return false;
    }

    final url = Uri.parse('${ApiService.baseUrl}/token/refresh');
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({'refresh_token': _refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['access_token'];

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', _token!);
        return true;
      } else {
        await logout();
        _sessionExpiredController.add(true);
        return false;
      }
    } catch (e) {
      return false;
    }
  }
}
