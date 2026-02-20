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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService(),
      builder: (context, _) {
        return MaterialApp(
          title: 'Epub Reader',
          debugShowCheckedModeBanner: false,

          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFFCF8F8),
            primaryColor: const Color(0xFFF5AFAF),

            colorScheme: const ColorScheme.light(
              primary: Color(0xFFF5AFAF),
              onPrimary: Colors.white,
              surface: Color(0xFFFBEFEF),
              onSurface: Colors.black87,
            ),

            cardColor: const Color(0xFFFBEFEF),

            dividerColor: const Color(0xFFF9DFDF),
            dividerTheme: const DividerThemeData(
              color: Color(0xFFF9DFDF),
              thickness: 0.5,
              space: 0,
            ),

            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFFCF8F8),
              foregroundColor: Colors.black87,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),

            inputDecorationTheme: const InputDecorationTheme(
              filled: true,
              fillColor: Color(0xFFF9DFDF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide.none,
              ),
            ),

            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5AFAF),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,

            scaffoldBackgroundColor: const Color(0xFF18122B),

            primaryColor: const Color(0xFF635985),

            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF635985),
              onPrimary: Colors.white,
              surface: Color(0xFF393053),
              onSurface: Colors.white70,
            ),

            cardColor: const Color(0xFF393053),

            dividerColor: const Color(0xFF443C68).withOpacity(0.5),
            dividerTheme: DividerThemeData(
              color: const Color(0xFF443C68).withOpacity(0.5),
              thickness: 0.5,
              space: 0,
            ),

            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF18122B),
              foregroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
            ),

            drawerTheme: const DrawerThemeData(
              backgroundColor: Color(0xFF18122B),
            ),

            inputDecorationTheme: const InputDecorationTheme(
              filled: true,
              fillColor: Color(0xFF443C68),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide.none,
              ),
            ),

            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF635985),
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
