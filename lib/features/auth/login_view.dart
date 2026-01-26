import 'package:flutter/material.dart';
import 'login_viewmodel.dart'; // <--- Import the VM

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  // The View keeps the ViewModel
  final LoginViewModel _viewModel = LoginViewModel();

  // The View keeps UI-specific controllers (TextEditingController is a UI element)
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passController.dispose();
    _viewModel.dispose(); // Clean up VM
    super.dispose();
  }

  void _onLoginPressed() async {
    // 1. View delegates logic to ViewModel
    final success = await _viewModel.login(
      _emailController.text.trim(),
      _passController.text.trim(),
    );

    if (!mounted) return;

    // 2. View handles Navigation (UI logic) based on result
    if (success) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder rebuilds ONLY this subtree when ViewModel calls notifyListeners()
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, child) {
        return Scaffold(
          appBar: AppBar(title: const Text("Login")),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.menu_book_rounded,
                    size: 80,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 40),

                  // INPUTS
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: "Email",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_viewModel.isLoading, // Disable when loading
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _passController,
                    decoration: const InputDecoration(
                      labelText: "Password",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock),
                    ),
                    obscureText: true,
                    enabled: !_viewModel.isLoading,
                  ),

                  // ERROR MESSAGE
                  if (_viewModel.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _viewModel.errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  const SizedBox(height: 24),

                  // LOGIN BUTTON
                  ElevatedButton(
                    onPressed: _viewModel.isLoading ? null : _onLoginPressed,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _viewModel.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text("Sign In"),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
