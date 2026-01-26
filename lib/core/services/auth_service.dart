import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // REMINDER: Use http://10.0.2.2:8000 for Android Emulator
  // Use your computer's IP (e.g., http://192.168.1.5:8000) for physical devices
  static const String _baseUrl = "http://10.0.2.2:8000";

  String? _accessToken;
  String? _refreshToken;
  String? _username; // <--- NEW: Variable to hold the username

  // Stream to notify UI when session expires (Refresh failed)
  final _sessionExpiredController = StreamController<bool>.broadcast();
  Stream<bool> get sessionExpiredStream => _sessionExpiredController.stream;

  String? get token => _accessToken;
  String? get username => _username; // <--- NEW: Getter
  bool get isLoggedIn => _accessToken != null;

  /// Load tokens AND username from storage on app start
  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString('auth_token');
    _refreshToken = prefs.getString('refresh_token');
    _username = prefs.getString('auth_username'); // <--- NEW: Load from disk
  }

  /// 1. Login Request
  Future<bool> login(String email, String password) async {
    try {
      final url = Uri.parse('$_baseUrl/token');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'username': email, 'password': password},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Save Tokens
        await _saveTokens(data['access_token'], data['refresh_token']);

        // NEW: Save Username (Email) locally so we can show it in the drawer
        _username = email;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_username', email);

        return true;
      }
      return false;
    } catch (e) {
      print("Login Error: $e");
      return false;
    }
  }

  /// 2. Refresh Token Logic
  Future<bool> tryRefreshToken() async {
    if (_refreshToken == null) return false;

    try {
      final url = Uri.parse('$_baseUrl/refresh');
      print("DEBUG: Attempting to refresh token...");

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': _refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Save the new access token AND the new refresh token (if rotated)
        await _saveTokens(data['access_token'], data['refresh_token']);
        print("DEBUG: Refresh successful!");
        return true;
      } else {
        print("DEBUG: Refresh failed. Session expired.");
        _sessionExpiredController.add(true); // Notify UI
        await logout(); // Clear data immediately
        return false;
      }
    } catch (e) {
      print("Refresh Network Error: $e");
      return false;
    }
  }

  Future<void> _saveTokens(String access, String? refresh) async {
    _accessToken = access;
    if (refresh != null) _refreshToken = refresh;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', _accessToken!);
    if (_refreshToken != null) {
      await prefs.setString('refresh_token', _refreshToken!);
    }
  }

  /// Logout
  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _username = null; // <--- NEW: Clear memory

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('refresh_token');
    await prefs.remove('auth_username'); // <--- NEW: Clear disk
  }
}
