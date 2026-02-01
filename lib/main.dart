import 'package:flutter/material.dart';
import 'features/home/home_view.dart';
import 'core/services/theme_service.dart';
import 'core/services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Load Theme Preference
  await ThemeService().loadTheme();

  // 2. Load Auth Token (for internal state, but we don't route based on it)
  await AuthService().init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Listen to ThemeService changes to trigger app-wide rebuilds
    return AnimatedBuilder(
      animation: ThemeService(),
      builder: (context, _) {
        return MaterialApp(
          title: 'Epub Reader',
          debugShowCheckedModeBanner: false,

          // --- LIGHT THEME ---
          theme: ThemeData(
            brightness: Brightness.light,
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Colors.white,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0,
            ),
          ),

          // --- DARK THEME ---
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: const Color(0xFF121212),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1E1E1E),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            drawerTheme: const DrawerThemeData(
              backgroundColor: Color(0xFF1E1E1E),
            ),
          ),

          // --- THEME MODE SWITCHER ---
          themeMode: ThemeService().themeMode,

          // --- HOME SCREEN ---
          // Always start at Home. The Home view handles the "Guest" vs "User" state.
          home: const HomeView(),
        );
      },
    );
  }
}
