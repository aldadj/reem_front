import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../utils/platform_helper.dart';
import '../theme/reem_theme.dart';
import 'chat_screen.dart';
import 'edit_profile_screen.dart';
import 'package:file_picker/file_picker.dart';
import '../services/account_service.dart';
import '../widgets/account_dialogs.dart';
import '../utils/media_url.dart';
import 'auth_screen.dart';
// import 'package:image_picker/image_picker.dart'; // Commenté pour désactiver la sélection d'image
import '../models/video.dart' as app_models;
import '../services/auth_service.dart';
import '../services/session_manager.dart';
import '../services/user_service.dart';
import '../widgets/video_player_item.dart';
import '../widgets/video_thumbnail.dart';
import '../screens/auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  final int userId;

  /// true quand l'écran est l'onglet Profil de la navigation (sans barre du haut)
  final bool embedded;

  /// Déconnexion (proposée dans le menu de son propre profil)
  final VoidCallback? onLogout;

  const ProfileScreen({
    super.key,
    required this.userId,
    this.embedded = false,
    this.onLogout,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with WidgetsBindingObserver {
  final SessionManager _sessionManager = SessionManager();
  final UserService _userService = UserService();

  Map<String, dynamic>? _profile;
  List<dynamic> _videos = [];
  List<dynamic> _likedVideos = [];
  bool _isLoading = true;
  bool _isLoadingLikes = false;
  bool _isFollowLoading = false;
  bool _pulseFollow = false;
  bool _showProfileUpdatedBanner = false;
  Timer? _refreshTimer;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfile();
    // Sur son propre profil : rafraîchit en silence (nouveaux abonnés, likes...)
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && _isOwnProfile && !_isLoading) _loadProfile(silent: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !_isLoading) {
      _loadProfile(silent: true);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadProfile({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    final token = _sessionManager.authToken;

    final profile = await _userService.fetchProfile(widget.userId, token: token);
    final videos = await _userService.fetchUserVideos(widget.userId, token: token);

    if (!mounted) return;
    setState(() {
      // En rafraîchissement silencieux, on garde l'ancien contenu si le réseau échoue
      if (profile != null || !silent) _profile = profile;
      if (profile != null || videos.isNotEmpty || !silent) _videos = videos;
      _sortVideos();
      _isLoading = false;
    });

    if (_isOwnProfile) {
      _loadLikedVideos(silent: true);
    }
  }

  bool _isPinned(dynamic video) {
    if (video is! Map) return false;
    return video['pinned_at'] != null || video['is_pinned'] == true;
  }

  // Vidéos épinglées en premier (la plus récemment épinglée d'abord)
  void _sortVideos() {
    final pinned = _videos.where(_isPinned).toList()
      ..sort((a, b) => '${b['pinned_at']}'.compareTo('${a['pinned_at']}'));
    final others = _videos.where((v) => !_isPinned(v)).toList();
    _videos = [...pinned, ...others];
  }

  Future<void> _togglePin(Map<String, dynamic> video) async {
    final token = _sessionManager.authToken;
    if (token == null) return;

    final result = await _userService.togglePin(video['id'] as int, token);
    if (!mounted) return;

    if (result['ok'] == true) {
      final pinned = result['pinned'] == true;
      setState(() {
        video['is_pinned'] = pinned;
        video['pinned_at'] =
            pinned ? (result['pinned_at'] ?? DateTime.now().toIso8601String()) : null;
        _sortVideos();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(pinned ? 'Vidéo épinglée' : 'Vidéo désépinglée'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${result['message']}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showVideoMenu(Map<String, dynamic> video) {
    final pinned = _isPinned(video);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121B2D),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(pinned ? Icons.push_pin_outlined : Icons.push_pin, color: Colors.white),
              title: Text(
                pinned ? 'Désépingler' : 'Épingler en haut du profil',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _togglePin(video);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Supprimer', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(sheetContext);
                _deleteVideo(video['id']);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleProfileUpdated(Map<String, dynamic> updatedUser) {
    _sessionManager.setUser(updatedUser);
    setState(() {
      _profile = {...?_profile, ...updatedUser};
      _showProfileUpdatedBanner = true;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _showProfileUpdatedBanner = false);
    });
  }

  void _openEditProfileSheet() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          initialName: _profile?['name']?.toString() ?? '',
          initialUsername: _profile?['username']?.toString() ?? '',
          initialBio: _profile?['bio']?.toString() ?? '',
          initialWebsite: _profile?['website']?.toString() ?? '',
          initialPhotoUrl: _profile?['profile_photo_path']?.toString(),
          onProfileUpdated: _handleProfileUpdated,
        ),
      ),
    );
  }

  Future<void> _loadLikedVideos({bool silent = false}) async {
    if (!silent) setState(() => _isLoadingLikes = true);
    final token = _sessionManager.authToken;
    final likedVideos = await _userService.fetchLikedVideos(token: token);

    if (!mounted) return;
    setState(() {
      _likedVideos = likedVideos;
      _isLoadingLikes = false;
    });
  }

  Future<void> _toggleFollow() async {
    if (!_sessionManager.isAuthenticated) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      return;
    }

    setState(() => _isFollowLoading = true);
    final result = await _userService.toggleFollow(widget.userId, _sessionManager.authToken!);

    if (!mounted) return;
    if (result != null) {
      setState(() {
        _profile?['is_following'] = result['following'];
        _profile?['followers_count'] = result['followers_count'];
      });

      final bool followed = result['following'] == true;
      setState(() => _pulseFollow = true);
      Future.delayed(const Duration(milliseconds: 260), () {
        if (mounted) setState(() => _pulseFollow = false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(followed ? 'Vous êtes abonné' : 'Abonnement annulé'),
          backgroundColor: followed ? Colors.green : Colors.grey[800],
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur réseau'), behavior: SnackBarBehavior.floating),
      );
    }

    setState(() => _isFollowLoading = false);
  }


  String? _convertPhotoUrl(String? photoPath) {
    if (photoPath == null) return null;
    if (isAndroidPlatform && (photoPath.contains('localhost') || photoPath.contains('127.0.0.1'))) {
      photoPath = photoPath.replaceAll('localhost', '10.0.2.2').replaceAll('127.0.0.1', '10.0.2.2');
    }
    if (!photoPath.startsWith('http')) {
      final domain = AuthService.baseUrl.replaceFirst(RegExp(r'/api$'), '');
      photoPath = domain + (photoPath.startsWith('/') ? '' : '/') + photoPath;
    }
    return photoPath;
  }

  String _profileHandle() {
    final username = _profile?['username']?.toString().trim();
    if (username != null && username.isNotEmpty) return '@$username';
    final name = _profile?['name']?.toString().trim() ?? 'utilisateur';
    final handle = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return '@${handle.isEmpty ? 'utilisateur' : handle}';
  }

  String _profileBio() {
    final bio = _profile?['bio']?.toString().trim();
    if (bio != null && bio.isNotEmpty) return bio;
    final email = _profile?['email']?.toString().trim();
    if (email != null && email.isNotEmpty) return email;
    return 'Partage des vidéos créatives et inspirantes.';
  }

  bool get _isOwnProfile {
    final currentUserId = _sessionManager.currentUser?['id'];
    return currentUserId != null && currentUserId == widget.userId;
  }

  String _compact(dynamic raw) {
    final value = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(value >= 10000000 ? 0 : 1)} M';
    if (value >= 10000) return '${(value / 1000).toStringAsFixed(value >= 100000 ? 0 : 1)} k';
    return '$value';
  }

  Widget _buildStatColumn(String value, String label) {
    return SizedBox(
      width: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: ReemColors.textMuted, fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _statDivider() => Container(width: 1, height: 22, color: Colors.white12);

  void _showProfileMenu() {
    Widget item(IconData icon, String label, VoidCallback onTap, {Color color = Colors.white}) {
      return ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color)),
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
      );
    }

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              item(Icons.edit_outlined, 'Modifier le profil', _openEditProfileSheet),
              item(Icons.camera_alt_outlined, 'Changer la photo de profil', _changePhotoQuick),
              item(Icons.lock_reset_rounded, 'Changer le mot de passe', () => showChangePasswordDialog(context)),
              item(Icons.refresh_rounded, 'Actualiser', () => _loadProfile(silent: true)),
              if (widget.onLogout != null)
                item(Icons.logout_rounded, 'Déconnexion', widget.onLogout!),
              const Divider(),
              item(Icons.delete_forever_rounded, 'Supprimer mon compte', () => showDeleteAccountDialog(context), color: ReemColors.like),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _openMessage() {
    if (!_sessionManager.isAuthenticated) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthScreen()));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserId: widget.userId,
          otherUserName: _profile?['name']?.toString() ?? 'Utilisateur',
        ),
      ),
    );
  }

  // Appui sur la photo de son propre profil : choisir et envoyer une nouvelle photo
  Future<void> _changePhotoQuick() async {
    if (!_isOwnProfile || _uploadingPhoto) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    if (file.size > 5 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La photo est trop lourde (5 Mo maximum).')),
      );
      return;
    }

    setState(() => _uploadingPhoto = true);
    try {
      final user = await AccountService().uploadPhoto(file.bytes!, file.name);
      if (!mounted) return;
      setState(() => _profile = {...?_profile, ...user});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo de profil mise à jour.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Widget _buildProfileHeader() {
    final String displayName = _profile?['name']?.toString() ?? 'Utilisateur';
    final String? photo = _convertPhotoUrl(_profile?['profile_photo_path']);
    final bool isFollowing = _profile?['is_following'] == true;
    final String bio = _profileBio();

    return Column(
      children: [
        if (_isOwnProfile)
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Menu',
              icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 28),
              onPressed: _showProfileMenu,
            ),
          )
        else
          const SizedBox(height: 8),
        GestureDetector(
          onTap: _isOwnProfile ? _changePhotoQuick : null,
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: ReemColors.gradient),
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: ReemColors.surfaceHigh,
                  backgroundImage: absoluteMediaUrl(photo) != null ? NetworkImage(absoluteMediaUrl(photo)!) : null,
                  child: absoluteMediaUrl(photo) == null
                      ? const Icon(Icons.person_rounded, color: Colors.white70, size: 48)
                      : null,
                ),
              ),
              if (_uploadingPhoto)
                const Positioned.fill(
                  child: ClipOval(
                    child: ColoredBox(
                      color: Colors.black54,
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                    ),
                  ),
                ),
              if (_isOwnProfile && !_uploadingPhoto)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: ReemColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: ReemColors.background, width: 3),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          displayName,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          _profileHandle(),
          style: const TextStyle(color: ReemColors.textMuted, fontSize: 13.5),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildStatColumn(_compact(_profile?['following_count']), 'Suivis'),
            _statDivider(),
            _buildStatColumn(_compact(_profile?['followers_count']), 'Abonnés'),
            _statDivider(),
            _buildStatColumn(_compact(_profile?['total_likes_count']), 'J’aime'),
          ],
        ),
        const SizedBox(height: 18),
        if (_isOwnProfile)
          SizedBox(
            width: 240,
            child: ElevatedButton.icon(
              onPressed: _openEditProfileSheet,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Modifier le profil'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: _pulseFollow ? 1.06 : 1.0,
                duration: const Duration(milliseconds: 180),
                child: SizedBox(
                  width: 190,
                  child: ElevatedButton.icon(
                    onPressed: _isFollowLoading ? null : _toggleFollow,
                    icon: _isFollowLoading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(isFollowing ? Icons.check_rounded : Icons.person_add_alt_1_rounded, size: 19),
                    label: Text(isFollowing ? 'Abonné(e)' : 'S’abonner'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isFollowing ? Colors.white.withValues(alpha: 0.12) : ReemColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _openMessage,
                  child: const Padding(
                    padding: EdgeInsets.all(13),
                    child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
        if (bio.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              bio,
              textAlign: TextAlign.center,
              style: const TextStyle(color: ReemColors.textSecondary, fontSize: 14, height: 1.4),
            ),
          ),
        if (_showProfileUpdatedBanner)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF1F9D63).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, color: Color(0xFF3DDC97), size: 18),
                  SizedBox(width: 8),
                  Text('Profil mis à jour', style: TextStyle(color: Color(0xFF3DDC97), fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
      ],
    );
  }

  String _serverBaseUrl() {
    return AuthService.baseUrl.replaceFirst(RegExp(r'/api$'), '');
  }

  String _videoThumbnailUrl(Map<String, dynamic> video) {
    final String thumbnailPath = video['thumbnail_path'] ?? '';
    if (thumbnailPath.isEmpty) return '';
    if (thumbnailPath.startsWith('http')) return thumbnailPath;
    return '${_serverBaseUrl()}${thumbnailPath.startsWith('/') ? '' : '/'}$thumbnailPath';
  }

  Widget _buildVideoThumbnail(String thumbnailUrl, String videoUrl) {
    return VideoThumbnail(
      thumbnailUrl: thumbnailUrl,
      videoUrl: videoUrl,
    );
  }

  String _videoMediaUrl(Map<String, dynamic> video) {
    final String rawPath = (video['video_url'] ?? video['video_path'] ?? '').toString();
    if (rawPath.isEmpty) return '';
    if (rawPath.startsWith('http')) return rawPath;
    return '${_serverBaseUrl()}${rawPath.startsWith('/') ? '' : '/'}$rawPath';
  }

  app_models.Video _buildVideoModel(Map<String, dynamic> video) {
    final Map<String, dynamic> copy = Map<String, dynamic>.from(video);
    final String mediaUrl = _videoMediaUrl(copy);
    if (mediaUrl.isNotEmpty) {
      copy['video_url'] = mediaUrl;
    }
    return app_models.Video.fromJson(copy);
  }

  Future<void> _deleteVideo(int videoId) async {
    if (!_sessionManager.isAuthenticated || _sessionManager.authToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connectez-vous pour supprimer une vidéo.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        title: const Text('Supprimer cette vidéo ?'),
        content: const Text('Cette action est définitive.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await _userService.deleteVideo(videoId, _sessionManager.authToken!);
    if (!mounted) return;

    if (success) {
      setState(() {
        _videos.removeWhere((video) => video['id'] == videoId);
        _likedVideos.removeWhere((video) => video['id'] == videoId);
        if (_profile != null && _profile!['videos_count'] != null) {
          _profile!['videos_count'] = (_profile!['videos_count'] as int) - 1;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vidéo supprimée.'), behavior: SnackBarBehavior.floating),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de supprimer la vidéo.'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Widget _buildVideosGrid(List<dynamic> videos, {required String emptyMessage, bool showOwnerMenu = false}) {
    if (videos.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadProfile(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 100),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  emptyMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 5
            : constraints.maxWidth >= 760
                ? 4
                : 3;
        return RefreshIndicator(
          onRefresh: () => _loadProfile(silent: true),
          child: GridView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: videos.length,
            // Grandes vignettes pleine largeur façon TikTok, 3 par ligne
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
              childAspectRatio: 0.7,
            ),
            itemBuilder: (context, index) {
              final video = videos[index] as Map<String, dynamic>;
              final thumbnailUrl = _videoThumbnailUrl(video);
              final String mediaUrl = _videoMediaUrl(video);
              final pinned = _isPinned(video);
              return GestureDetector(
                onTap: mediaUrl.isEmpty
                    ? null
                    : () {
                        final videoModel = _buildVideoModel(video);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VideoPlayerItem(
                              video: videoModel,
                              feedVisible: ValueNotifier<bool>(true),
                            ),
                          ),
                        );
                      },
                onLongPress: showOwnerMenu ? () => _showVideoMenu(video) : null,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: const Color(0xFF0F172A)),
                    Positioned.fill(child: _buildVideoThumbnail(thumbnailUrl, mediaUrl)),
                    // Dégradé bas pour lire le compteur
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 56,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black.withValues(alpha: 0.65), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    if (pinned)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.push_pin, color: Colors.white, size: 11),
                              SizedBox(width: 3),
                              Text('Épinglé',
                                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    if (showOwnerMenu)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => _showVideoMenu(video),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.more_vert, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Row(
                        children: [
                          const Icon(Icons.favorite, color: Colors.white, size: 14),
                          const SizedBox(width: 3),
                          Text(
                            '${video['likes_count'] ?? 0}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ReemColors.background,
      appBar: widget.embedded ? null : AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Profil', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz, color: Colors.white70),
            onPressed: _isOwnProfile ? _showProfileMenu : null,
          ),
        ],
      ),
      body: _wideCenter(_isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _profile == null
              ? const Center(child: Text('Impossible de charger le profil', style: TextStyle(color: Colors.white)))
              : DefaultTabController(
                  length: 2,
                  child: NestedScrollView(
                    headerSliverBuilder: (context, innerBoxIsScrolled) => [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: _buildProfileHeader(),
                        ),
                      ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _ProfileTabsDelegate(
                      Container(
                        color: ReemColors.background,
                        child: TabBar(
                          indicatorColor: ReemColors.primary,
                          indicatorWeight: 3,
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.white12,
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.white38,
                          tabs: const [
                            Tab(icon: Icon(Icons.grid_view_rounded), height: 46),
                            Tab(icon: Icon(Icons.favorite_border_rounded), height: 46),
                          ],
                        ),
                      ),
                        ),
                      ),
                    ],
                    body: TabBarView(
                          children: [
                            Padding(
                              padding: EdgeInsets.zero,
                              child: _buildVideosGrid(
                                _videos,
                                emptyMessage: _isOwnProfile
                                    ? 'Vous n’avez pas encore publié de vidéos.'
                                    : 'Aucune vidéo trouvée.',
                                showOwnerMenu: _isOwnProfile,
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.zero,
                              child: _isOwnProfile
                                  ? (_isLoadingLikes
                                      ? const Center(child: CircularProgressIndicator(color: Colors.white))
                                      : _buildVideosGrid(
                                          _likedVideos,
                                          emptyMessage: 'Vous n’avez pas encore aimé de vidéos.',
                                        ))
                                  : const Center(
                                      child: Text(
                                        'Les vidéos aimées sont privées.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                  ),
                )),
    );
  }

  /// Sur ordinateur, le contenu reste centré (pas de vidéos géantes)
  Widget _wideCenter(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: child,
      ),
    );
  }
}

/// Colle la barre d'onglets (Publications / Aimés) en haut pendant le défilement.
class _ProfileTabsDelegate extends SliverPersistentHeaderDelegate {
  _ProfileTabsDelegate(this.child);

  final Widget child;

  @override
  double get minExtent => 47;

  @override
  double get maxExtent => 47;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;

  @override
  bool shouldRebuild(covariant _ProfileTabsDelegate oldDelegate) => true;
}
