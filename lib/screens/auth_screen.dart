import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'photo_crop_screen.dart';
import 'package:flutter/material.dart';
import '../theme/reem_theme.dart';
import '../theme/reem_logo.dart';
// import 'package:image_picker/image_picker.dart'; // Commenté pour désactiver la sélection d'image
import '../services/auth_service.dart';
import '../services/google_sign_in_service.dart';
import '../services/session_manager.dart';
import 'feed_screen.dart';
import 'login_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';
  Uint8List? _photoBytes;
  String? _photoName;

  final AuthService _authService = AuthService();
  final GoogleSignInService _googleSignInService = GoogleSignInService();
  final SessionManager _sessionManager = SessionManager();

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    if (!mounted) return;
    final cropped = await cropProfilePhoto(context, file.bytes!);
    if (cropped == null || !mounted) return;
    setState(() {
      _photoBytes = cropped;
      _photoName = 'photo_profil.png';
      _errorMessage = '';
    });
  }

  Future<void> _register() async {
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'Les mots de passe ne correspondent pas');
      return;
    }

    if (_nameController.text.isEmpty || _emailController.text.isEmpty) {
      setState(() => _errorMessage = 'Veuillez remplir tous les champs');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await _authService.register(
        _nameController.text,
        _emailController.text,
        _passwordController.text,
        imageBytes: _photoBytes,
        imageName: _photoName,
      );

      if (response != null && response.containsKey('access_token')) {
        // Stockage du token et de l'utilisateur
        _sessionManager.setSession(
          response['access_token'],
          response['user'] ?? {},
        );

        // Inscription réussie, aller au flux vidéo
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const FeedScreen()),
          );
        }
      } else {
        setState(() => _errorMessage = 'Erreur lors de l\'inscription');
      }
    } catch (e) {
      // On retire le préfixe "Exception: " si présent pour un affichage propre
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _continueWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final googleIdToken = await _googleSignInService.signInAndGetIdToken();
      if (googleIdToken == null) {
        setState(() => _errorMessage = 'Connexion Google annulée ou impossible.');
        return;
      }

      final response = await _authService.loginWithGoogle(googleIdToken);

      if (response != null && response.containsKey('access_token')) {
        _sessionManager.setSession(
          response['access_token'],
          response['user'] ?? {},
        );

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const FeedScreen()),
          );
        }
      } else {
        setState(() => _errorMessage = 'Connexion Google impossible pour le moment.');
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.reem.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: context.reem.text),
          onPressed: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const FeedScreen()),
            );
          },
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [context.isDarkMode ? const Color(0xFF2A1650) : const Color(0xFFE6D9FB), context.reem.background],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: context.reem.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: context.reem.text.withValues(alpha: 0.06)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.24),
                    blurRadius: 24,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              // Logo/Titre
              const SizedBox(height: 40),
              const ReemLogo(),
              const SizedBox(height: 12),
              Text(
                'Partage tes vidéos',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.reem.textMuted,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 48),

              // Sélecteur d'image
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: context.reem.surfaceHigh,
                    backgroundImage: _photoBytes != null ? MemoryImage(_photoBytes!) : null,
                    child: _photoBytes == null
                        ? Icon(Icons.add_a_photo, color: context.reem.text, size: 30)
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Champ Nom
              TextField(
                controller: _nameController,
                style: TextStyle(color: context.reem.text),
                decoration: InputDecoration(
                  hintText: 'Nom complet',
                  hintStyle: TextStyle(color: context.reem.textMuted),
                  prefixIcon: Icon(Icons.person, color: context.reem.textMuted),
                ),
              ),
              const SizedBox(height: 16),

              // Champ Email
              TextField(
                controller: _emailController,
                style: TextStyle(color: context.reem.text),
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'Email',
                  hintStyle: TextStyle(color: context.reem.textMuted),
                  prefixIcon: Icon(Icons.email, color: context.reem.textMuted),
                ),
              ),
              const SizedBox(height: 16),

              // Champ Mot de passe
              TextField(
                controller: _passwordController,
                style: TextStyle(color: context.reem.text),
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Mot de passe',
                  hintStyle: TextStyle(color: context.reem.textMuted),
                  prefixIcon: Icon(Icons.lock, color: context.reem.textMuted),
                ),
              ),
              const SizedBox(height: 16),

              // Champ Confirmation mot de passe
              TextField(
                controller: _confirmPasswordController,
                style: TextStyle(color: context.reem.text),
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Confirmer le mot de passe',
                  hintStyle: TextStyle(color: context.reem.textMuted),
                  prefixIcon: Icon(Icons.lock, color: context.reem.textMuted),
                ),
              ),
              const SizedBox(height: 24),

              // Message d'erreur
              if (_errorMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 24),

              // Bouton S'inscrire
              ElevatedButton(
                onPressed: _isLoading ? null : _register,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ReemColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Text(
                        'S\'inscrire',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 16),

              // Séparateur visuel
              Row(
                children: [
                  Expanded(child: Divider(color: context.reem.textMuted)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('OU', style: TextStyle(color: context.reem.textMuted)),
                  ),
                  Expanded(child: Divider(color: context.reem.textMuted)),
                ],
              ),
              const SizedBox(height: 16),

              // Bouton Google
              OutlinedButton.icon(
                onPressed: _isLoading || !GoogleSignInService.isSupportedPlatform
                    ? null
                    : _continueWithGoogle,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.reem.text,
                  side: BorderSide(color: context.reem.border),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Image.network(
                  'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/24px-Google_%22G%22_logo.svg.png',
                  height: 24,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.account_circle),
                ),
                label: const Text('Continuer avec Google'),
              ),
              const SizedBox(height: 16),
              if (!GoogleSignInService.isSupportedPlatform)
                Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Google Sign-In non supporté sur Windows. Testez sur Android, iOS ou Web.',
                    style: TextStyle(color: context.reem.textSecondary, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),

              // Lien vers connexion
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Tu as déjà un compte ? ',
                    style: TextStyle(color: context.reem.textMuted),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    },
                    child: Text(
                      'Connexion',
                      style: TextStyle(
                        color: context.reem.text,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    ),
  ),
);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
