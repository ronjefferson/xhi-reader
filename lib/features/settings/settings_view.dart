import 'package:flutter/material.dart';
import '../../core/services/theme_service.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService(),
      builder: (context, _) {
        final isDark = ThemeService().isDarkMode;

        return Scaffold(
          appBar: AppBar(title: const Text("Settings")),
          body: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text(
                  "Appearance",
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SwitchListTile(
                title: const Text("Dark Mode"),
                subtitle: const Text("Switch between light and dark themes"),
                value: isDark,
                onChanged: (val) {
                  ThemeService().toggleTheme(val);
                },
                secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
              ),
            ],
          ),
        );
      },
    );
  }
}
