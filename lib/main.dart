import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:camera/camera.dart';
import 'dart:io' show Platform;
import 'package:reem_front/screens/feed_screen.dart';

// Liste globale pour rendre les caméras accessibles dans toute l'application (notamment UploadScreen)
List<CameraDescription> cameras = [];

void main() async {
  // 1. ASSURE L'INITIALISATION DES WIDGETS (Obligatoire avant du code asynchrone dans le main)
  WidgetsFlutterBinding.ensureInitialized();

  // 2. INITIALISE MEDIA_KIT POUR LA LECTURE VIDÉO
  MediaKit.ensureInitialized();

  // 3. RÉCUPÈRE LES CAMÉRAS DISPONIBLES SUR L'APPAREIL (uniquement sur les plateformes mobiles)
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      cameras = await availableCameras();
    } catch (e) {
      print("Erreur lors de l'initialisation des caméras : $e");
    }
  } else {
    // Sur les plateformes non mobiles (comme Windows), la caméra n'est pas supportée par ce plugin.
    print("La fonctionnalité de caméra n'est pas supportée sur cette plateforme.");
  }

  // Note: J'ai retiré MyHttpOverrides car il n'est pas pertinent pour le design.
  // Si vous en avez besoin pour l'API, vous pouvez le remettre.

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'REEM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B1020),
        primaryColor: const Color(0xFF7C9BFF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C9BFF),
          secondary: Color(0xFF8B5CF6),
          background: Color(0xFF0B1020),
          surface: Color(0xFF121B2D),
        ),
        iconTheme: const IconThemeData(color: Colors.white, size: 24),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          bodyMedium: TextStyle(color: Colors.white70, fontSize: 14),
          titleMedium: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF121B2D),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          hintStyle: const TextStyle(color: Colors.white38),
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7C9BFF),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF121B2D),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
      ),
      home: FeedScreen(), // On démarre sur notre nouvel écran principal
    );
  }
}