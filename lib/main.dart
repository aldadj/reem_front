import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/splash_screen.dart';
import 'theme/reem_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  runApp(const ReemApp());
}

class ReemApp extends StatelessWidget {
  const ReemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'REEM',
      theme: ReemTheme.dark(),
      darkTheme: ReemTheme.dark(),
      themeMode: ThemeMode.dark,
      scrollBehavior: const ReemScrollBehavior(),
      home: const SplashScreen(),
    );
  }
}
