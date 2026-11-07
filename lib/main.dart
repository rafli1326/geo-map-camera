import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/camera_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI style (dark navigation bar & status bar)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0B1326),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Lock portrait window orientation (UI & watermark rotate in-place via accelerometer)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(const GPSMapCameraApp());
}

class GPSMapCameraApp extends StatelessWidget {
  const GPSMapCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Geo Map Camera',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B1326),
        primaryColor: const Color(0xFFFFC174),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFC174),
          onPrimary: Color(0xFF472A00),
          secondary: Color(0xFF4EDEA3),
          surface: Color(0xFF131B2E),
          surfaceContainerLowest: Color(0xFF0B1326),
        ),
        fontFamily: GoogleFonts.chivo().fontFamily,
        useMaterial3: true,
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xF018181B),
          contentTextStyle: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const CameraScreen(),
    );
  }
}
