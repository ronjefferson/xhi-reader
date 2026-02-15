import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdfrx/pdfrx.dart'; // Required
import 'package:path_provider/path_provider.dart'; // Required

import './features/home/home_view.dart';
import 'core/services/theme_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/upload_service.dart';
import 'core/services/download_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Theme
  await ThemeService().loadTheme();

  // 2. Initialize Auth
  await AuthService().init();

  // 🟢 3. CORRECT CONFIGURATION FOR PDF CACHE
  // We assign a FUNCTION that returns the path, not the path itself.
  Pdfrx.getCacheDirectory = () async {
    final dir = await getApplicationCacheDirectory();
    return dir.path;
  };

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UploadService()),
        ChangeNotifierProvider(create: (_) => DownloadService()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
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

          themeMode: ThemeService().themeMode,
          home: const HomeView(),
        );
      },
    );
  }
}
