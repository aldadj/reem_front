import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'video_interaction_store.dart';

/// Session de l'utilisateur. Le jeton et le profil sont gardés sur l'appareil :
/// on reste connecté après avoir quitté l'application, jusqu'à la déconnexion.
class SessionManager {
  static final SessionManager _instance = SessionManager._internal();

  static const String _tokenKey = 'session_token';
  static const String _userKey = 'session_user';

  String? _authToken;
  Map<String, dynamic>? _currentUser;

  factory SessionManager() => _instance;

  SessionManager._internal();

  String? get authToken => _authToken;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isAuthenticated => _authToken != null;

  /// À appeler une fois au démarrage de l'application.
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      if (token == null || token.isEmpty) return;

      _authToken = token;
      final stored = prefs.getString(_userKey);
      if (stored != null) {
        _currentUser = Map<String, dynamic>.from(jsonDecode(stored) as Map);
      }
      _refreshInBackground();
    } catch (_) {
      // Sans stockage disponible, on reste simplement déconnecté
    }
  }

  // Vérifie que le compte est toujours valide et rafraîchit le profil.
  // Hors connexion : on garde la session (pas de déconnexion par erreur réseau).
  Future<void> _refreshInBackground() async {
    final token = _authToken;
    if (token == null) return;
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/user'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
      );
      if (response.statusCode == 401) {
        clearSession();
      } else if (response.statusCode == 200) {
        final user = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
        _currentUser = {...?_currentUser, ...user};
        _save();
      }
    } catch (_) {}
  }

  void setSession(String token, Map<String, dynamic> user) {
    _authToken = token;
    _currentUser = user;
    _save();
  }

  void setUser(Map<String, dynamic> user) {
    _currentUser = user;
    _save();
  }

  void clearSession() {
    _authToken = null;
    _currentUser = null;
    FollowCache.clear();
    _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_authToken == null) {
        await prefs.remove(_tokenKey);
        await prefs.remove(_userKey);
      } else {
        await prefs.setString(_tokenKey, _authToken!);
        if (_currentUser != null) await prefs.setString(_userKey, jsonEncode(_currentUser));
      }
    } catch (_) {}
  }
}
