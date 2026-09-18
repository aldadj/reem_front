import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
// import 'package:image_picker/image_picker.dart'; // Commenté pour désactiver la sélection d'image
import '../services/session_manager.dart';
import '../services/auth_service.dart';
import '../widgets/video_player_item.dart';
import '../models/video.dart' as app_models;
import 'upload_screen.dart';
import 'auth_screen.dart';
import 'messages_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<dynamic> _videos = [];
  List<dynamic> _friendsVideos = [];
  List<dynamic> _exploreVideos = [];
  List<dynamic> _userVideos = [];
  bool _isLoading = true;
  bool _isLoadingExplore = false;
  bool _isLoadingUserVideos = false;
  bool _isUpdatingPhoto = false;
  int _currentIndex = 0;
  int _profileTabIndex = 0;
  int _currentBottomIndex = 0;
  int _unreadNotificationsCount = 0;
  final ValueNotifier<bool> _isFeedVisible = ValueNotifier<bool>(true);
  final SessionManager _sessionManager = SessionManager();
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _fetchVideos();
    _fetchUnreadNotificationsCount();
  }

  Future<void> _fetchVideos() async {
    setState(() => _isLoading = true);
    final String apiUrl = "${AuthService.baseUrl}/videos";
    try {
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: _sessionManager.isAuthenticated
            ? {'Authorization': 'Bearer ${_sessionManager.authToken}'}
            : null,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final videos = List<dynamic>.from(data['data'] ?? []);
        videos.shuffle();
        setState(() {
          _videos = videos;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print("Erreur lors de la récupération des vidéos : $e");
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _fetchUserVideos() async {
    if (!_sessionManager.isAuthenticated) return;
    
    setState(() => _isLoadingUserVideos = true);
    final String apiUrl = "${AuthService.baseUrl}/user/videos";
    
    try {
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'Authorization': 'Bearer ${_sessionManager.authToken}'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _userVideos = data; 
        });
      }
    } catch (e) {
      print("Erreur vidéos utilisateur : $e");
    } finally {
      setState(() => _isLoadingUserVideos = false);
    }
  }

  Future<void> _fetchFriendsVideos() async {
    if (!_sessionManager.isAuthenticated) {
      setState(() => _friendsVideos = []);
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/videos/friends'),
        headers: {'Authorization': 'Bearer ${_sessionManager.authToken}'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final videos = List<dynamic>.from(data['data'] ?? []);
        setState(() {
          _friendsVideos = videos;
        });
      }
    } catch (e) {
      print('Erreur amis vidéos : $e');
    }
  }

  Future<void> _fetchExploreVideos() async {
    setState(() => _isLoadingExplore = true);
    final String apiUrl = "${AuthService.baseUrl}/videos";

    try {
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: _sessionManager.isAuthenticated
            ? {'Authorization': 'Bearer ${_sessionManager.authToken}'}
            : null,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _exploreVideos = data['data'] ?? [];
        });
      }
    } catch (e) {
      print("Erreur exploration vidéos : $e");
    } finally {
      setState(() => _isLoadingExplore = false);
    }
  }

  Future<void> _fetchUnreadNotificationsCount() async {
    if (!_sessionManager.isAuthenticated) {
      setState(() => _unreadNotificationsCount = 0);
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/notifications'),
        headers: {
          'Authorization': 'Bearer ${_sessionManager.authToken}',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> notifications = jsonDecode(response.body);
        final int count = notifications.where((notification) {
          return notification['read_at'] == null;
        }).length;
        setState(() => _unreadNotificationsCount = count);
      }
    } catch (e) {
      print('Erreur récupération notifications non lues : $e');
    }
  }

  void _updateUnreadNotificationsCount(int count) {
    setState(() => _unreadNotificationsCount = count);
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text(
            'Déconnexion',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Êtes-vous sûr de vouloir vous déconnecter ?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () {
                _sessionManager.clearSession();
                Navigator.of(context).pop();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                );
              },
              child: const Text('Déconnexion', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text('Choisir une nouvelle photo', style: TextStyle(color: Colors.white)),
              // Appel à la fonction commentée désactivé
              onTap: null,
            ),
            if (_sessionManager.currentUser?['profile_photo_path'] != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Supprimer la photo actuelle', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deletePhoto();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deletePhoto() async {
    setState(() => _isUpdatingPhoto = true);
    try {
      final response = await _authService.deleteProfilePhoto(_sessionManager.authToken!);
      if (response != null && response.containsKey('user')) {
        _sessionManager.setUser(response['user']);
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo supprimée')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      setState(() => _isUpdatingPhoto = false);
    }
  }

  // Future<void> _pickAndUploadPhoto() async {
  //   final picker = ImagePicker();
  //   final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    
  //   if (pickedFile != null) {
  //     setState(() => _isUpdatingPhoto = true);
  //     try {
  //       final response = await _authService.updateProfilePhoto(
  //         _sessionManager.authToken!,
  //         pickedFile.path,
  //       );

  //       if (response != null && response.containsKey('user')) {
  //         _sessionManager.setUser(response['user']);
  //         setState(() {}); // Rafraîchir l'UI avec la nouvelle photo
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           const SnackBar(content: Text('Photo de profil mise à jour !')),
  //         );
  //       }
  //       } catch (e) {
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           SnackBar(content: Text('Erreur: $e')),
  //         );
  //       } finally {
  //         setState(() => _isUpdatingPhoto = false);
  //       }
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1A2E),
      extendBodyBehindAppBar: false,
      extendBody: false,

      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1020),
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 0,
        leading: const SizedBox.shrink(),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF7C9BFF).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.auto_awesome, color: Color(0xFF7C9BFF), size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              "REEM",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, color: Colors.white70, size: 24),
            onPressed: () {
              print("🔍 Clic sur recherche");
            },
          ),
          const SizedBox(width: 8),
        ],
      ),

      body: _currentBottomIndex == 4
          ? _buildProfileScreen()
          : _currentBottomIndex == 3
              ? MessagesScreen(onUnreadCountChanged: _updateUnreadNotificationsCount)
              : _buildFeedScreen(),

      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF0F1628),
        elevation: 0,
        unselectedItemColor: Colors.white38,
        selectedItemColor: const Color(0xFF7C9BFF),
        selectedIconTheme: const IconThemeData(size: 24, color: Color(0xFF7C9BFF)),
        showSelectedLabels: true,
        showUnselectedLabels: false,
        currentIndex: _currentBottomIndex,
        onTap: (index) {
          if (index == 2) {
            // Vérifier si l'utilisateur est connecté avant de publier
            if (_sessionManager.isAuthenticated) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const UploadScreen()),
              ).then((_) => _fetchVideos());
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AuthScreen()),
              );
            }
          } else {
            if (index == 0) {
              _isFeedVisible.value = true;
              _fetchVideos();
            } else if (index == 1) {
              _isFeedVisible.value = true;
              _fetchFriendsVideos();
            } else {
              _isFeedVisible.value = false;
            }

            setState(() {
              _currentBottomIndex = index;
              if (index == 3) {
                _fetchUnreadNotificationsCount();
              }
              if (index == 4) {
                _fetchUserVideos();
                _fetchExploreVideos();
              }
            });
          }
        },
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Accueil'),
          const BottomNavigationBarItem(icon: Icon(Icons.group_outlined), label: 'Ami(e)s'),
          BottomNavigationBarItem(
            icon: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF7C9BFF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
            ),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.forum_outlined),
                if (_unreadNotificationsCount > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFF7C9BFF),
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Text(
                        _unreadNotificationsCount > 99 ? '99+' : '$_unreadNotificationsCount',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Messages',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profil'),
        ],
      ),
    );
  }

  Widget _buildFeedScreen() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF7C9BFF)));
    }

    final List<dynamic> sourceVideos = _currentBottomIndex == 1 ? _friendsVideos : _videos;

    if (sourceVideos.isEmpty) {
      return _buildEmptyState();
    }

    final shuffledVideos = List<dynamic>.from(sourceVideos);

    return RefreshIndicator(
      onRefresh: _currentBottomIndex == 1 ? _fetchFriendsVideos : _fetchVideos,
      color: const Color(0xFF7C9BFF),
      child: PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: shuffledVideos.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        itemBuilder: (context, index) {
          final video = shuffledVideos[index];
          final String rawPath = video['video_path'] ?? '';
          final String cleanPath = rawPath.replaceAll('\\', '/');
          final String fullVideoUrl = "http://127.0.0.1:8000$cleanPath";

          final videoModel = app_models.Video(
            id: video['id'],
            videoUrl: fullVideoUrl,
            title: video['title'] ?? '',
            description: video['description'],
            username: video['user'] != null ? video['user']['name'] : 'Anonyme',
            authorId: video['user'] != null ? video['user']['id'] ?? 0 : 0,
            likesCount: video['likes_count'] ?? 0,
            commentsCount: video['comments_count'] ?? 0,
            isLiked: video['liked_by_user'] ?? false,
            isFavorited: video['favorited_by_user'] ?? false,
          );

          return VideoPlayerItem(
            video: videoModel,
            feedVisible: _isFeedVisible,
            showBackButton: false,
          );
        },
      ),
    );
  }

  Widget _buildProfileAvatar(Map<String, dynamic>? user) {
    String? photoPath = user?['profile_photo_path'];
    if (photoPath != null) {
      if (Platform.isAndroid && (photoPath.contains('localhost') || photoPath.contains('127.0.0.1'))) {
        photoPath = photoPath.replaceAll('localhost', '10.0.2.2').replaceAll('127.0.0.1', '10.0.2.2');
      }
      if (!photoPath.startsWith('http')) {
        final domain = Platform.isAndroid ? "http://10.0.2.2:8000" : "http://127.0.0.1:8000";
        photoPath = domain + (photoPath.startsWith('/') ? '' : '/') + photoPath;
      }
    }

    return Stack(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey[800],
            border: Border.all(color: Colors.white, width: 2),
            image: photoPath != null 
              ? DecorationImage(image: NetworkImage(photoPath), fit: BoxFit.cover) 
              : null,
          ),
          child: _isUpdatingPhoto 
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : (photoPath == null ? const Icon(Icons.person, size: 60, color: Colors.white) : null),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: _isUpdatingPhoto ? null : _showPhotoOptions,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt, size: 18, color: Colors.black),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileScreen() {
    final user = _sessionManager.currentUser;
    final bool isGuest = !_sessionManager.isAuthenticated;

    if (isGuest) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_outline, size: 80, color: Colors.grey),
              const SizedBox(height: 24),
              const Text(
                "Inscrivez-vous pour voir votre profil",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                "Créez un compte pour partager vos propres vidéos et interagir avec la communauté.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AuthScreen()),
                    );
                  },
                  child: const Text("S'inscrire / Se connecter", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 80),
          
          _buildProfileAvatar(user),
          const SizedBox(height: 24),

          // Nom utilisateur
          Text(
            user?['name'] ?? 'Utilisateur',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // Email
          Text(
            user?['email'] ?? '',
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),

          // Stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatColumn(_userVideos.length.toString(), 'Publications'),
              _buildStatColumn('0', 'Abonné(e)s'),
              _buildStatColumn('0', 'Abonnements'),
            ],
          ),
          const SizedBox(height: 32),

          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _profileTabIndex = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _profileTabIndex == 0 ? Colors.white : Colors.white12,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Publications',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _profileTabIndex == 0 ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _profileTabIndex = 1);
                    if (_exploreVideos.isEmpty) {
                      _fetchExploreVideos();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _profileTabIndex == 1 ? Colors.white : Colors.white12,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Explorer',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _profileTabIndex == 1 ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (_profileTabIndex == 0) ...[
            _buildProfileList(
              title: 'Vos publications',
              items: _userVideos,
              isLoading: _isLoadingUserVideos,
            ),
          ] else ...[
            _buildProfileList(
              title: 'Vidéos aléatoires',
              items: _exploreVideos,
              isLoading: _isLoadingExplore,
            ),
          ],

          const SizedBox(height: 24),

          // Bouton Modifier le profil
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                // TODO: Implémenter la modification du profil
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Fonctionnalité à venir')),
                );
              },
              child: const Text(
                'Modifier le profil',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Bouton Déconnexion
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _logout,
              child: const Text(
                'Déconnexion',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _isFeedVisible.dispose();
    super.dispose();
  }

  Widget _buildProfileList({
    required String title,
    required List<dynamic> items,
    required bool isLoading,
  }) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
    }

    if (items.isEmpty) {
      return Column(
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            'Aucune vidéo trouvée.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(color: Colors.white24),
          itemBuilder: (context, index) {
            final video = items[index];
            final String rawPath = video['video_path'] ?? '';
            final String cleanPath = rawPath.replaceAll('\\', '/');
            final String thumbnailPath = video['thumbnail_path'] ?? '';
            final String thumbnailUrl = thumbnailPath.startsWith('http')
                ? thumbnailPath
                : "http://127.0.0.1:8000${thumbnailPath.startsWith('/') ? '' : '/'}$thumbnailPath";
            final String fullVideoUrl = "http://127.0.0.1:8000$cleanPath";

            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 100,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white12,
                  image: thumbnailPath.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(thumbnailUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: thumbnailPath.isEmpty
                    ? const Icon(Icons.play_arrow, color: Colors.white)
                    : null,
              ),
              title: Text(video['title'] ?? 'Sans titre', style: const TextStyle(color: Colors.white)),
              subtitle: Text(video['description'] ?? '', style: const TextStyle(color: Colors.grey)),
              trailing: Text(
                '${video['likes_count'] ?? 0} ❤',
                style: const TextStyle(color: Colors.white70),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoPlayerItem(
                      video: app_models.Video(
                        id: video['id'],
                        videoUrl: fullVideoUrl,
                        title: video['title'] ?? '',
                        description: video['description'],
                        username: video['user'] != null ? video['user']['name'] : 'Anonyme',
                        authorId: video['user'] != null ? video['user']['id'] ?? 0 : 0,
                        likesCount: video['likes_count'] ?? 0,
                        commentsCount: video['comments_count'] ?? 0,
                        isLiked: video['liked_by_user'] ?? false,
                        isFavorited: video['favorited_by_user'] ?? false,
                      ),
                      feedVisible: _isFeedVisible,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF121B2D),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.videocam_outlined, color: Color(0xFF7C9BFF), size: 34),
            ),
            const SizedBox(height: 18),
            const Text("Aucune vidéo disponible.", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text("Publiez une première vidéo pour alimenter votre fil.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C9BFF)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const UploadScreen()),
                ).then((_) => _fetchVideos());
              },
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text("Publier une vidéo", style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }
}