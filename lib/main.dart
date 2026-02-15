import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:path_provider/path_provider.dart';

import './features/home/home_view.dart';
import 'core/services/theme_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/upload_service.dart';
import 'core/services/download_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeService().loadTheme();
  await AuthService().init();

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

  static const Color customButtonColor = Color.fromARGB(255, 175, 126, 209);

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
            primaryColor: Colors.blue,

            colorScheme: const ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              surface: Colors.white,
            ),

            scaffoldBackgroundColor: Colors.white,
            cardColor: Colors.white,

            // 1. SOFT DIVIDERS (Global)
            dividerColor: Colors.black.withOpacity(0.05),
            dividerTheme: DividerThemeData(
              color: Colors.black.withOpacity(0.05),
              thickness: 1,
              space: 1,
            ),

            // 🟢 2. SOFT APP BAR LINE (Light)
            appBarTheme: AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0, // No shadow
              scrolledUnderElevation: 0, // No color change on scroll
              shape: Border(
                bottom: BorderSide(
                  color: Colors.black.withOpacity(0.05), // Subtle Border
                  width: 1,
                ),
              ),
            ),

            drawerTheme: const DrawerThemeData(
              backgroundColor: Colors.white,
              elevation: 0,
            ),

            listTileTheme: const ListTileThemeData(
              textColor: Colors.black,
              iconColor: Colors.black,
            ),

            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.grey[100],
              hintStyle: TextStyle(color: Colors.grey[600]),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),

            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: customButtonColor,
                foregroundColor: Colors.white,
              ),
            ),
          ),

          // --- DARK THEME ---
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.blue,
            primaryColor: const Color.fromARGB(255, 79, 53, 80),

            colorScheme: const ColorScheme.dark(
              primary: Colors.blue,
              onPrimary: Colors.white,
              surface: Color(0xFF1B121E),
            ),

            scaffoldBackgroundColor: const Color.fromARGB(255, 27, 18, 30),
            cardColor: const Color.fromARGB(255, 27, 18, 30),

            // 1. SOFT DIVIDERS (Global)
            dividerColor: Colors.white.withOpacity(0.1),
            dividerTheme: DividerThemeData(
              color: Colors.white.withOpacity(0.1),
              thickness: 1,
              space: 1,
            ),

            // 🟢 2. SOFT APP BAR LINE (Dark)
            appBarTheme: AppBarTheme(
              backgroundColor: const Color.fromARGB(255, 27, 18, 30),
              foregroundColor: Colors.white,
              elevation: 0, // No shadow
              scrolledUnderElevation: 0,
              shape: Border(
                bottom: BorderSide(
                  color: Colors.white.withOpacity(0.1), // Subtle Border
                  width: 1,
                ),
              ),
            ),

            drawerTheme: const DrawerThemeData(
              backgroundColor: Color.fromARGB(255, 27, 18, 30),
            ),

            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color.fromARGB(255, 42, 36, 44),
              hintStyle: const TextStyle(color: Colors.grey),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),

            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: customButtonColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          themeMode: ThemeService().themeMode,
          home: const HomeView(),
        );
      },
    );
  }
}
