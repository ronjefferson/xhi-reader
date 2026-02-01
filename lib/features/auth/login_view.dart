import 'package:flutter/material.dart';
import '../../core/services/auth_service.dart';
import 'register_view.dart'; // Import the new view

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  void _handleLogin() async {
    setState(() => _isLoading = true);

    final success = await AuthService().login(
      _usernameController.text,
      _passwordController.text,
    );

    setState(() => _isLoading = false);

    if (success) {
      if (mounted) Navigator.pop(context, true);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Login Failed")));
      }
    }
  }

  // Navigate to Register View
  void _goToRegister() async {
    // We wait for result in case we want to pre-fill the email after registration
    final createdEmail = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegisterView()),
    );

    if (createdEmail != null && createdEmail is String) {
      _usernameController.text = createdEmail;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: "Email / Username"),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: "Password"),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              ElevatedButton(
                onPressed: _handleLogin,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text("Login"),
              ),

            // 🟢 NEW: Create Account Button
            const SizedBox(height: 20),
            TextButton(
              onPressed: _goToRegister,
              child: const Text("Don't have an account? Create one"),
            ),
          ],
        ),
      ),
    );
  }
}
