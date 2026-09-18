import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleSignInService {
  static bool get isSupportedPlatform =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  // TODO: Remplacez cette valeur par votre OAuth 2.0 Client ID Web Google.
  static const String _googleClientId =
      'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    clientId: _googleClientId,
    serverClientId: _googleClientId,
  );

  Future<String?> signInAndGetIdToken() async {
    if (!isSupportedPlatform) {
      throw UnsupportedError(
        'Google Sign-In n’est pas supporté sur cette plateforme. Utilisez un appareil Android, iOS ou Web.',
      );
    }

    final account = await _googleSignIn.signIn();
    if (account == null) {
      return null;
    }

    final auth = await account.authentication;
    return auth.idToken;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }
}
