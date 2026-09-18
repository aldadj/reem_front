import 'dart:io';

import 'package:flutter/material.dart';
// import 'package:image_picker/image_picker.dart'; // Commenté pour désactiver la sélection d'image
import '../models/video.dart' as app_models;
import '../services/auth_service.dart';
import '../services/session_manager.dart';
import '../services/user_service.dart';
import '../widgets/video_player_item.dart';
import '../screens/auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  final int userId;

  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final token = _sessionManager.authToken;

    final profile = await _userService.fetchProfile(widget.userId, token: token);
    final videos = await _userService.fetchUserVideos(widget.userId, token: token);

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _videos = videos;
      _isLoading = false;
    });

    if (_isOwnProfile) {
      _loadLikedVideos();
    }
  }


  void _handleProfileUpdated(Map<String, dynamic> updatedUser) {
    _sessionManager.setUser(updatedUser);
    setState(() {
      _profile = updatedUser;
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
          initialPhotoUrl: _convertPhotoUrl(_profile?['profile_photo_path']),
          onProfileUpdated: _handleProfileUpdated,
        ),
      ),
    );
  }

  Future<void> _loadLikedVideos() async {
    setState(() => _isLoadingLikes = true);
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
    if (Platform.isAndroid && (photoPath.contains('localhost') || photoPath.contains('127.0.0.1'))) {
      photoPath = photoPath.replaceAll('localhost', '10.0.2.2').replaceAll('127.0.0.1', '10.0.2.2');
    }
    if (!photoPath.startsWith('http')) {
      final domain = Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000';
      photoPath = domain + (photoPath.startsWith('/') ? '' : '/') + photoPath;
    }
    return photoPath;
  }

  String _profileHandle() {
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

  Widget _buildStatColumn(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
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

  Widget _buildVideosGrid(List<dynamic> videos, {required String emptyMessage, bool showDeleteButton = false}) {
    if (videos.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.only(top: 8),
      shrinkWrap: true,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: videos.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 0.65,
      ),
      itemBuilder: (context, index) {
        final video = videos[index] as Map<String, dynamic>;
        final thumbnailUrl = _videoThumbnailUrl(video);
        final String mediaUrl = _videoMediaUrl(video);
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                image: thumbnailUrl.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(thumbnailUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (thumbnailUrl.isNotEmpty)
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.center,
                          colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
                        ),
                      ),
                    )
                  else
                    const Center(
                      child: Icon(Icons.videocam_outlined, color: Colors.white54, size: 32),
                    ),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
                    ),
                  ),
                  if (showDeleteButton)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: () => _deleteVideo(video['id']),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.all(6),
                          child: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${video['likes_count'] ?? 0} ❤',
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _profile?['name'] ?? 'Utilisateur';
    final displayHandle = _profileHandle();
    final bioText = _profileBio();

    return Scaffold(
      backgroundColor: const Color(0xFF0B1020),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Profil', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz, color: Colors.white70),
            onPressed: () {},
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _profile == null
              ? const Center(child: Text('Impossible de charger le profil', style: TextStyle(color: Colors.white)))
              : DefaultTabController(
                  length: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF121B2D),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    CircleAvatar(
                                      radius: 46,
                                      backgroundColor: const Color(0xFF1D2742),
                                      backgroundImage: _convertPhotoUrl(_profile?['profile_photo_path']) != null
                                          ? NetworkImage(_convertPhotoUrl(_profile?['profile_photo_path'])!)
                                          : null,
                                      child: _convertPhotoUrl(_profile?['profile_photo_path']) == null
                                          ? const Icon(Icons.person, color: Colors.white, size: 42)
                                          : null,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                                          const SizedBox(height: 6),
                                          Text(displayHandle, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                                          const SizedBox(height: 14),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              _buildStatColumn('${_profile?['videos_count'] ?? 0}', 'Vidéos'),
                                              _buildStatColumn('${_profile?['followers_count'] ?? 0}', 'Abonnés'),
                                              _buildStatColumn('${_profile?['following_count'] ?? 0}', 'Suivis'),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(bioText, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _isOwnProfile ? const Color(0xFF7C9BFF) : (_profile?['is_following'] == true ? Colors.white : const Color(0xFF7C9BFF)),
                                        foregroundColor: _isOwnProfile ? Colors.white : (_profile?['is_following'] == true ? Colors.black : Colors.white),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                      onPressed: _isOwnProfile ? _openEditProfileSheet : (_isFollowLoading ? null : _toggleFollow),
                                      child: AnimatedScale(
                                        scale: _pulseFollow ? 1.05 : 1.0,
                                        duration: const Duration(milliseconds: 200),
                                        curve: Curves.easeOut,
                                        child: _isFollowLoading && !_isOwnProfile
                                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                            : Text(
                                                _isOwnProfile ? 'Modifier le profil' : (_profile?['is_following'] == true ? 'Abonné' : 'S’abonner'),
                                                style: const TextStyle(fontWeight: FontWeight.bold),
                                              ),
                                      ),
                                    ),
                                  ),
                                  if (!_isOwnProfile) ...[
                                    const SizedBox(width: 12),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF121B2D),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                      ),
                                      child: IconButton(
                                        onPressed: () {},
                                        icon: const Icon(Icons.send, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (_showProfileUpdatedBanner)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12, top: 12),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.green[700],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.check_circle, color: Colors.white, size: 20),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'Profil mis à jour !',
                                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 26),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF1D2742), Color(0xFF7C9BFF)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.white24,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.flash_on, color: Colors.white, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: const [
                                          Text('REEM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
                                          SizedBox(height: 4),
                                          Text(
                                            'Une présence créative plus élégante et cohérente.',
                                            style: TextStyle(color: Colors.white70, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {},
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        textStyle: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      child: const Text('Découvrir'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        color: const Color(0xFF0B1020),
                        child: TabBar(
                          indicatorColor: const Color(0xFF7C9BFF),
                          indicatorWeight: 3,
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.white54,
                          tabs: const [
                            Tab(icon: Icon(Icons.grid_on), text: 'Publications'),
                            Tab(icon: Icon(Icons.favorite_border), text: 'Aimés'),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              child: _buildVideosGrid(
                                _videos,
                                emptyMessage: _isOwnProfile
                                    ? 'Vous n’avez pas encore publié de vidéos.'
                                    : 'Aucune vidéo trouvée.',
                                showDeleteButton: _isOwnProfile,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                    ],
                  ),
                ),
    );
  }
}
class EditProfileScreen extends StatefulWidget {
  final String initialName;
  final String? initialPhotoUrl;
  final void Function(Map<String, dynamic>) onProfileUpdated;

  const EditProfileScreen({
    super.key,
    required this.initialName,
    this.initialPhotoUrl,
    required this.onProfileUpdated,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final SessionManager _sessionManager = SessionManager();
  final TextEditingController _nameController = TextEditingController();
  String? _selectedPhotoPath;
  String? _currentPhotoUrl;
  bool _isUpdating = false;
  bool _isDeletingPhoto = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName;
    _currentPhotoUrl = widget.initialPhotoUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // Future<void> _pickProfilePhoto() async {
  //   final picker = ImagePicker();
  //   final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
  //   if (pickedFile != null && mounted) {
  //     setState(() {
  //       _selectedPhotoPath = pickedFile.path;
  //     });
  //   }
  // }

  Future<void> _saveProfileChanges() async {
    if (!_sessionManager.isAuthenticated || _sessionManager.authToken == null) {
      return;
    }

    final token = _sessionManager.authToken!;
    final currentName = widget.initialName.trim();
    final newName = _nameController.text.trim();
    final shouldUpdateName = newName.isNotEmpty && newName != currentName;
    final shouldUpdatePhoto = _selectedPhotoPath != null;

    if (!shouldUpdateName && !shouldUpdatePhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun changement détecté.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() => _isUpdating = true);
    final updatedUser = Map<String, dynamic>.from(_sessionManager.currentUser ?? {});

    try {
      if (shouldUpdatePhoto) {
        final photoResponse = await AuthService().updateProfilePhoto(token, _selectedPhotoPath!);
        if (photoResponse != null && photoResponse.containsKey('user')) {
          updatedUser.addAll(Map<String, dynamic>.from(photoResponse['user'] as Map<String, dynamic>));
        }
      }

      if (shouldUpdateName) {
        final profileResponse = await AuthService().updateProfileInfo(token, newName);
        if (profileResponse != null && profileResponse.containsKey('user')) {
          updatedUser.addAll(Map<String, dynamic>.from(profileResponse['user'] as Map<String, dynamic>));
        }
      }

      if (!mounted) return;
      if (updatedUser.isNotEmpty) {
        widget.onProfileUpdated(updatedUser);
      }

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil mis à jour avec succès.'), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur de mise à jour: $e'), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _deleteCurrentProfilePhoto() async {
    if (_selectedPhotoPath != null) {
      setState(() {
        _selectedPhotoPath = null;
      });
      return;
    }

    if (!_sessionManager.isAuthenticated || _sessionManager.authToken == null) {
      return;
    }

    if (_currentPhotoUrl == null) {
      return;
    }

    setState(() => _isDeletingPhoto = true);
    try {
      final response = await AuthService().deleteProfilePhoto(_sessionManager.authToken!);
      if (response != null && response.containsKey('user')) {
        final updatedUser = Map<String, dynamic>.from(response['user'] as Map<String, dynamic>);
        if (!mounted) return;
        setState(() {
          _currentPhotoUrl = null;
          _selectedPhotoPath = null;
        });
        widget.onProfileUpdated(updatedUser);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo de profil supprimée.'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de supprimer la photo: $e'), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) {
        setState(() => _isDeletingPhoto = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = _selectedPhotoPath != null ? null : _currentPhotoUrl;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Modifier le profil', style: TextStyle(color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Nom',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Colors.white12,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 24),
            if (_selectedPhotoPath != null || imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _selectedPhotoPath != null
                    ? Image.file(File(_selectedPhotoPath!), width: double.infinity, height: 220, fit: BoxFit.cover)
                    : Image.network(imageUrl!, width: double.infinity, height: 220, fit: BoxFit.cover),
              ),
            if (_selectedPhotoPath != null || imageUrl != null) const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: null, // _pickProfilePhoto, // Désactivé
              icon: const Icon(Icons.photo_library),
              label: const Text('Choisir une nouvelle photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            if (_selectedPhotoPath != null || imageUrl != null)
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _isDeletingPhoto ? null : _deleteCurrentProfilePhoto,
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  label: Text(
                    _selectedPhotoPath != null ? 'Annuler la sélection' : 'Supprimer la photo actuelle',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white12,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isUpdating ? null : _saveProfileChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: _isUpdating
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
