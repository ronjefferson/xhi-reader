import 'package:flutter/material.dart';
import '../../core/services/auth_service.dart';

class RegisterViewModel extends ChangeNotifier {
  bool isLoading = false;
  String? errorMessage;

  Future<bool> register(String email, String password) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    final error = await AuthService().register(email, password);

    isLoading = false;
    
    if (error == null) {
      // Success
      return true;
    } else {
      // Failure
      errorMessage = error;
      notifyListeners();
      return false;
    }
  }
}