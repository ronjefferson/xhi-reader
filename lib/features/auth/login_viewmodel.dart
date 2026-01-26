import 'package:flutter/foundation.dart';
import '../../core/services/auth_service.dart';

class LoginViewModel extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<bool> login(String email, String password) async {
    _setLoading(true);
    _setError(null);

    // Business Logic: Input Validation
    if (email.isEmpty || password.isEmpty) {
      _setError("Please enter both email and password.");
      _setLoading(false);
      return false;
    }

    // Interaction with Model (Service)
    final success = await AuthService().login(email, password);

    if (!success) {
      _setError("Invalid email or password.");
    }

    _setLoading(false);
    return success;
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String? msg) {
    _errorMessage = msg;
    notifyListeners();
  }
}
