
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'splash_screen.dart';
import '../services/app_settings.dart';
import '../services/session_manager.dart';
import '../theme/reem_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  await AppSettings.instance.load();
  await SessionManager().restore();

  runApp(const ReemApp());
}

class ReemApp extends StatelessWidget {
  const ReemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'REEM',
        theme: ReemTheme.light(),
        darkTheme: ReemTheme.dark(),
        themeMode: AppSettings.instance.themeMode,
        scrollBehavior: const ReemScrollBehavior(),
        home: const SplashScreen(),
      ),
    );
  }
}
