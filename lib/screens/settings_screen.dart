import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/session_manager.dart';
import '../theme/reem_theme.dart';
import '../utils/media_url.dart';
import '../widgets/account_dialogs.dart';
import 'edit_profile_screen.dart';
import 'login_screen.dart';

/// Paramètres de l'application. Tous les réglages sont enregistrés sur l'appareil
/// et appliqués tout de suite (thème, lecture, notifications affichées, confidentialité...).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onLogout});

  /// Déconnexion (fournie par le fil, qui remet l'app en mode invité)
  final VoidCallback? onLogout;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AppSettings _settings = AppSettings.instance;
  final SessionManager _session = SessionManager();

  static const String _appVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _settings.addListener(_refresh);
  }

  @override
  void dispose() {
    _settings.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------------
  // BRIQUES D'INTERFACE
  // ---------------------------------------------------------------------------

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: context.reem.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: context.reem.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.reem.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 56, color: context.reem.border),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? color,
  }) {
    final tint = color ?? context.reem.text;
    return ListTile(
      leading: Icon(icon, color: color ?? context.reem.textSecondary),
      title: Text(title, style: TextStyle(color: tint, fontWeight: FontWeight.w600)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: TextStyle(color: context.reem.textMuted, fontSize: 12.5)),
      trailing: trailing ??
          (onTap != null ? Icon(Icons.chevron_right_rounded, color: context.reem.textMuted) : null),
      onTap: onTap,
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: context.reem.textSecondary),
      title: Text(title, style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w600)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: TextStyle(color: context.reem.textMuted, fontSize: 12.5)),
      value: value,
      onChanged: onChanged,
    );
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  void _openEditProfile() {
    final user = _session.currentUser ?? {};
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          initialName: user['name']?.toString() ?? '',
          initialUsername: user['username']?.toString() ?? '',
          initialBio: user['bio']?.toString() ?? '',
          initialWebsite: user['website']?.toString() ?? '',
          initialPhotoUrl: user['profile_photo_path']?.toString(),
          onProfileUpdated: (updated) {
            _session.setUser(updated);
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text('Tu pourras te reconnecter à tout moment.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Annuler', style: TextStyle(color: context.reem.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Déconnexion', style: TextStyle(color: ReemColors.like)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    Navigator.of(context).pop();
    widget.onLogout?.call();
  }

  void _clearSearchHistory() {
    if (_settings.recentSearches.isEmpty) {
      _toast('Aucune recherche à effacer.');
      return;
    }
    _settings.update(_settings.recentSearches.clear);
    _toast('Historique de recherche effacé.');
  }

  void _showText(String title, String body) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body, style: const TextStyle(height: 1.45))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
        ],
      ),
    );
  }

  String _visibilityLabel(String value) {
    switch (value) {
      case 'friends':
        return 'Amis';
      case 'private':
        return 'Moi uniquement';
      default:
        return 'Tout le monde';
    }
  }

  Future<void> _chooseVisibility() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Qui peut voir mes nouvelles vidéos ?',
                  style: TextStyle(color: context.reem.text, fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            for (final option in const [
              ('public', Icons.public_rounded, 'Tout le monde'),
              ('friends', Icons.group_rounded, 'Amis (abonnement réciproque)'),
              ('private', Icons.lock_outline_rounded, 'Moi uniquement'),
            ])
              ListTile(
                leading: Icon(option.$2, color: context.reem.textSecondary),
                title: Text(option.$3, style: TextStyle(color: context.reem.text)),
                trailing: _settings.defaultVisibility == option.$1
                    ? const Icon(Icons.check_circle_rounded, color: ReemColors.primary)
                    : null,
                onTap: () => Navigator.pop(sheetContext, option.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice != null) _settings.update(() => _settings.defaultVisibility = choice);
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final signedIn = _session.isAuthenticated;
    final user = _session.currentUser;
    final photo = absoluteMediaUrl(user?['profile_photo_path']?.toString());
    final name = user?['name']?.toString() ?? 'Utilisateur';

    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              if (signedIn)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.reem.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: context.reem.border),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: context.reem.surfaceHigh,
                        backgroundImage: photo != null ? NetworkImage(photo) : null,
                        child: photo == null
                            ? Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w800, fontSize: 20),
                              )
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: context.reem.text, fontSize: 17, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              user?['email']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: context.reem.textMuted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              if (signedIn)
                _section('Compte', [
                  _tile(icon: Icons.edit_outlined, title: 'Modifier le profil', onTap: _openEditProfile),
                  _tile(
                    icon: Icons.lock_reset_rounded,
                    title: 'Changer le mot de passe',
                    onTap: () => showChangePasswordDialog(context),
                  ),
                ]),

              _section('Apparence', [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.brightness_6_outlined, color: context.reem.textSecondary),
                          const SizedBox(width: 16),
                          Text(
                            'Thème',
                            style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w600, fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<ThemeMode>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.phone_iphone_rounded, size: 18), label: Text('Auto')),
                            ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined, size: 18), label: Text('Clair')),
                            ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined, size: 18), label: Text('Sombre')),
                          ],
                          selected: {_settings.themeMode},
                          onSelectionChanged: (value) => _settings.update(() => _settings.themeMode = value.first),
                        ),
                      ),
                    ],
                  ),
                ),
              ]),

              _section('Lecture des vidéos', [
                _switchTile(
                  icon: Icons.play_circle_outline_rounded,
                  title: 'Lecture automatique',
                  subtitle: 'Les vidéos du fil démarrent toutes seules',
                  value: _settings.autoplay,
                  onChanged: (value) => _settings.update(() => _settings.autoplay = value),
                ),
                _switchTile(
                  icon: Icons.skip_next_rounded,
                  title: 'Enchaîner les vidéos',
                  subtitle: 'Passe à la suivante à la fin de la vidéo',
                  value: _settings.autoNext,
                  onChanged: (value) => _settings.update(() => _settings.autoNext = value),
                ),
              ]),

              if (signedIn)
                _section('Notifications affichées', [
                  _switchTile(
                    icon: Icons.favorite_border_rounded,
                    title: 'J’aime et favoris',
                    value: _settings.showLikeNotifications,
                    onChanged: (value) => _settings.update(() => _settings.showLikeNotifications = value),
                  ),
                  _switchTile(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Commentaires et réponses',
                    value: _settings.showCommentNotifications,
                    onChanged: (value) => _settings.update(() => _settings.showCommentNotifications = value),
                  ),
                  _switchTile(
                    icon: Icons.person_add_alt_1_outlined,
                    title: 'Nouveaux abonnés',
                    value: _settings.showFollowNotifications,
                    onChanged: (value) => _settings.update(() => _settings.showFollowNotifications = value),
                  ),
                ]),

              if (signedIn)
                _section('Confidentialité', [
                  _tile(
                    icon: Icons.visibility_outlined,
                    title: 'Visibilité de mes nouvelles vidéos',
                    subtitle: _visibilityLabel(_settings.defaultVisibility),
                    onTap: _chooseVisibility,
                  ),
                ]),

              _section('Données', [
                _tile(
                  icon: Icons.history_rounded,
                  title: 'Effacer l’historique de recherche',
                  subtitle: _settings.recentSearches.isEmpty
                      ? 'Aucune recherche enregistrée'
                      : '${_settings.recentSearches.length} recherche(s) enregistrée(s)',
                  onTap: _clearSearchHistory,
                ),
              ]),

              _section('Aide et informations', [
                _tile(
                  icon: Icons.description_outlined,
                  title: 'Conditions d’utilisation',
                  onTap: () => _showText(
                    'Conditions d’utilisation',
                    'En utilisant Reem, tu t’engages à publier uniquement des contenus dont tu es l’auteur ou pour lesquels tu as les droits, '
                    'et à respecter les autres membres.\n\n'
                    'Les contenus violents, haineux, illégaux ou qui portent atteinte à la vie privée d’autrui ne sont pas autorisés et peuvent être supprimés. '
                    'Un compte peut être suspendu en cas d’abus répété.\n\n'
                    'Tu restes responsable de ce que tu publies et tu peux supprimer tes vidéos et ton compte à tout moment.',
                  ),
                ),
                _tile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Confidentialité des données',
                  onTap: () => _showText(
                    'Confidentialité des données',
                    'Reem enregistre les informations de ton profil (nom, photo, bio), tes vidéos, tes commentaires, tes j’aime, tes abonnements et tes messages '
                    'pour faire fonctionner l’application.\n\n'
                    'Tu choisis qui voit tes vidéos (tout le monde, tes amis ou toi seul). '
                    'Tu peux modifier ton profil ou supprimer définitivement ton compte et toutes tes données depuis ces paramètres.',
                  ),
                ),
                _tile(
                  icon: Icons.info_outline_rounded,
                  title: 'À propos de Reem',
                  subtitle: 'Version $_appVersion',
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'Reem',
                    applicationVersion: _appVersion,
                    children: const [
                      SizedBox(height: 8),
                      Text('Crée, partage et découvre des vidéos.'),
                    ],
                  ),
                ),
              ]),

              if (signedIn)
                _section('Session', [
                  _tile(
                    icon: Icons.logout_rounded,
                    title: 'Se déconnecter',
                    onTap: widget.onLogout == null ? null : _confirmLogout,
                  ),
                  _tile(
                    icon: Icons.delete_forever_rounded,
                    title: 'Supprimer mon compte',
                    color: ReemColors.like,
                    onTap: () => showDeleteAccountDialog(context),
                  ),
                ])
              else
                Padding(
                  padding: const EdgeInsets.only(top: 22),
                  child: ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    child: const Text('Se connecter'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
