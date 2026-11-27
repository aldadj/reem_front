
import 'package:flutter/material.dart';

import 'splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const ReemApp());
}

class ReemApp extends StatelessWidget {
  const ReemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'REEM',
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
