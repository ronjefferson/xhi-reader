import 'package:flutter/material.dart';
// Import the Home Feature
import 'features/home/home_view.dart';

void main() {
  // Required for async plugins (permissions, file access) to work on startup
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const MyReaderApp());
}

class MyReaderApp extends StatelessWidget {
  const MyReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Reader',
      debugShowCheckedModeBanner: false,

      // Modern Material 3 Theme
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.grey[50],
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
          scrolledUnderElevation: 0,
        ),
      ),

      // Start directly at the Home View
      home: const HomeView(),
    );
  }
}
