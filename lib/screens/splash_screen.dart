import 'package:flutter/material.dart';
import '../services/session_manager.dart';
import 'feed_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final SessionManager _sessionManager = SessionManager();

  @override
  void initState() {
    super.initState();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    // Simule un délai pour afficher le splash screen
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    // On redirige maintenant tout le monde vers le FeedScreen par défaut
    // Le SessionManager gardera l'état (connecté ou invité)
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const FeedScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1A2E),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B1A2E), Color(0xFF111F34)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'REEM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 56,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.4,
                ),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Color(0xFF7C4DFF)),
              ),
              const SizedBox(height: 24),
              const Text(
                'Une expérience plus calme et élégante',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
