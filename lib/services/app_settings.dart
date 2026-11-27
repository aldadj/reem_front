import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Réglages de l'application, sauvegardés sur l'appareil.
/// Tout l'écran Paramètres lit et modifie cet objet.
class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  ThemeMode themeMode = ThemeMode.system;

  // Lecture
  bool autoplay = true; // les vidéos du fil démarrent toutes seules
  bool autoNext = false; // passe à la vidéo suivante à la fin

  // Notifications affichées
  bool showLikeNotifications = true; // j'aime et favoris
  bool showCommentNotifications = true;
  bool showFollowNotifications = true;

  // Confidentialité : visibilité proposée pour mes nouvelles vidéos
  String defaultVisibility = 'public'; // public | friends | private

  // Historique de recherche (gardé le temps de la session)
  final List<String> recentSearches = [];

  SharedPreferences? _prefs;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.name == prefs.getString('themeMode'),
        orElse: () => ThemeMode.system,
      );
      autoplay = prefs.getBool('autoplay') ?? true;
      autoNext = prefs.getBool('autoNext') ?? false;
      showLikeNotifications = prefs.getBool('showLikeNotifications') ?? true;
      showCommentNotifications = prefs.getBool('showCommentNotifications') ?? true;
      showFollowNotifications = prefs.getBool('showFollowNotifications') ?? true;
      defaultVisibility = prefs.getString('defaultVisibility') ?? 'public';
    } catch (_) {
      // Sans stockage disponible, les réglages restent ceux par défaut
    }
  }

  void _save() {
    final prefs = _prefs;
    if (prefs == null) return;
    prefs.setString('themeMode', themeMode.name);
    prefs.setBool('autoplay', autoplay);
    prefs.setBool('autoNext', autoNext);
    prefs.setBool('showLikeNotifications', showLikeNotifications);
    prefs.setBool('showCommentNotifications', showCommentNotifications);
    prefs.setBool('showFollowNotifications', showFollowNotifications);
    prefs.setString('defaultVisibility', defaultVisibility);
  }

  void update(VoidCallback change) {
    change();
    notifyListeners();
    _save();
  }

  /// Une notification doit-elle être affichée selon les réglages ?
  bool allowsNotificationType(String type) {
    switch (type) {
      case 'like':
      case 'favorite':
        return showLikeNotifications;
      case 'comment':
        return showCommentNotifications;
      case 'follow':
        return showFollowNotifications;
      default:
        return true;
    }
  }
}
