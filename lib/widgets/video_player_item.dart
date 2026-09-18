import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:http/http.dart' as http;
import '../services/session_manager.dart';
import '../services/auth_service.dart';
import '../screens/auth_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/profile_screen.dart';
import '../models/video.dart' as app_models; // On ajoute l'alias "app_models" ici

class VideoPlayerItem extends StatefulWidget {
  final app_models.Video video;
  final ValueNotifier<bool> feedVisible;
  final bool showBackButton;

  const VideoPlayerItem({
    Key? key,
    required this.video,
    required this.feedVisible,
    this.showBackButton = true,
  }) : super(key: key);

  @override
  State<VideoPlayerItem> createState() => _VideoPlayerItemState();
}

class _VideoPlayerItemState extends State<VideoPlayerItem> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Player player;
  late final VideoController controller;

  // État local pour TikTok feel
  bool _isLiked = false;
  bool _isFavorited = false;
  late int _likesCount;
  late int _commentsCount;
  final SessionManager _sessionManager = SessionManager();

  // Animation du coeur au centre
  late final AnimationController _heartController;
  late final Animation<double> _heartAnimation;
  bool _showHeart = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    player = Player();
    controller = VideoController(player);

    widget.feedVisible.addListener(_handleFeedVisibleChanged);

    _isLiked = widget.video.isLiked;
    _isFavorited = widget.video.isFavorited;
    _likesCount = widget.video.likesCount;
    _commentsCount = widget.video.commentsCount;

    player.open(Media(widget.video.videoUrl));
    player.setPlaylistMode(PlaylistMode.single);
    player.setVolume(1.0);
    if (widget.feedVisible.value) {
      player.play();
    }

    // Initialisation de l'animation du coeur
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _heartAnimation = CurvedAnimation(
      parent: _heartController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      player.pause();
    } else if (state == AppLifecycleState.resumed) {
      if (widget.feedVisible.value) {
        player.play();
      }
    }
  }

  void _handleFeedVisibleChanged() {
    if (mounted) {
      if (widget.feedVisible.value) {
        player.play();
      } else {
        player.pause();
      }
    }
    if (!widget.feedVisible.value && mounted) {
      player.pause();
    } else if (widget.feedVisible.value && mounted) {
      player.play();
    } 
  }

  Future<void> _toggleLike() async {
    if (!_sessionManager.isAuthenticated) {
      _goToAuth();
      return;
    }

    setState(() {
      _isLiked = !_isLiked;
      _isLiked ? _likesCount++ : _likesCount--;
    });

    try {
      final response = await http.post(
        Uri.parse("${AuthService.baseUrl}/videos/${widget.video.id}/like"),
        headers: {
          'Authorization': 'Bearer ${_sessionManager.authToken}',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode != 200) {
        // Rollback si erreur serveur
        setState(() {
          _isLiked = !_isLiked;
          _isLiked ? _likesCount++ : _likesCount--;
        });
      }
    } catch (e) {
      // En cas d'erreur réseau, on annule aussi l'action
      setState(() {
        _isLiked = !_isLiked;
        _isLiked ? _likesCount++ : _likesCount--;
      });
      print("Erreur Like: $e");
    }
  }

  Future<void> _toggleFavorite() async {
    if (!_sessionManager.isAuthenticated) {
      _goToAuth();
      return;
    }

    setState(() => _isFavorited = !_isFavorited);

    try {
      final response = await http.post(
        Uri.parse("${AuthService.baseUrl}/videos/${widget.video.id}/favorite"),
        headers: {
          'Authorization': 'Bearer ${_sessionManager.authToken}',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        setState(() => _isFavorited = !_isFavorited);
      }
    } catch (e) {
      print("Erreur Favoris: $e");
      setState(() => _isFavorited = !_isFavorited);
    }
  }

  void _openProfile() {
    if (widget.video.authorId == 0) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: widget.video.authorId),
      ),
    );
  }

  void _showCommentsBottomSheet() {
    final TextEditingController commentController = TextEditingController();
    List<dynamic> comments = [];
    bool isLoadingComments = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          // Charger les commentaires au premier affichage
          if (isLoadingComments) {
            http.get(Uri.parse("${AuthService.baseUrl}/videos/${widget.video.id}/comments")).then((res) {
              if (res.statusCode == 200) {
                setModalState(() {
                  comments = jsonDecode(res.body);
                  isLoadingComments = false;
                });
              }
            });
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Text("${comments.length} commentaires", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const Divider(color: Colors.white12),
                Expanded(
                  child: isLoadingComments 
                    ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
                    : ListView.builder(
                        itemCount: comments.length,
                        itemBuilder: (context, index) {
                          final c = comments[index];
                          final user = c['user'];
                          String? photoPath = user['profile_photo_path'];

                          // Mapping de l'URL pour l'émulateur Android et le domaine local
                          if (photoPath != null) {
                            if (Platform.isAndroid && (photoPath.contains('localhost') || photoPath.contains('127.0.0.1'))) {
                              photoPath = photoPath.replaceAll('localhost', '10.0.2.2').replaceAll('127.0.0.1', '10.0.2.2');
                            }
                            if (!photoPath.startsWith('http')) {
                              final domain = Platform.isAndroid ? "http://10.0.2.2:8000" : "http://127.0.0.1:8000";
                              photoPath = domain + (photoPath.startsWith('/') ? '' : '/') + photoPath;
                            }
                          }

                          final int? commenterId = c['user']?['id'];
                          final bool canReply = commenterId != null && commenterId != _sessionManager.currentUser?['id'];

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.grey[800],
                              backgroundImage: photoPath != null ? NetworkImage(photoPath) : null,
                              child: photoPath == null ? const Icon(Icons.person, color: Colors.white) : null,
                            ),
                            title: Row(
                              children: [
                                Text(c['user']['name'], style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                const SizedBox(width: 8),
                                Text(
                                  _formatTimeAgo(c['created_at']),
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                              ],
                            ),
                            subtitle: Text(c['comment'], style: const TextStyle(color: Colors.white)),
                            trailing: canReply
                                ? IconButton(
                                    icon: const Icon(Icons.reply, color: Colors.white70, size: 20),
                                    onPressed: () {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChatScreen(
                                            otherUserId: commenterId,
                                            otherUserName: c['user']['name'],
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                : null,
                          );
                        },
                      ),
                ),
                Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: commentController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: "Ajouter un commentaire...",
                            hintStyle: TextStyle(color: Colors.white54),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send, color: Colors.redAccent),
                        onPressed: () async {
                          if (commentController.text.trim().isEmpty) return;
                          if (!_sessionManager.isAuthenticated) {
                            Navigator.pop(context);
                            _goToAuth();
                            return;
                          }

                          final res = await http.post(
                            Uri.parse("${AuthService.baseUrl}/videos/${widget.video.id}/comments"),
                            headers: {
                              'Authorization': 'Bearer ${_sessionManager.authToken}',
                              'Content-Type': 'application/json',
                              'Accept': 'application/json',
                            },
                            body: jsonEncode({'comment': commentController.text}),
                          );

                          if (res.statusCode == 201) {
                            final newComment = jsonDecode(res.body);
                            setModalState(() {
                              comments.insert(0, newComment);
                              commentController.clear();
                            });
                            setState(() {
                              _commentsCount++;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatTimeAgo(String? dateString) {
    if (dateString == null) return "";
    try {
      // Laravel renvoie des dates en UTC, DateTime.parse les gère. 
      // .toLocal() convertit à l'heure du téléphone de l'utilisateur.
      DateTime dateTime = DateTime.parse(dateString).toLocal();
      Duration diff = DateTime.now().difference(dateTime);

      if (diff.inDays >= 7) {
        return "${dateTime.day}/${dateTime.month}";
      } else if (diff.inDays >= 1) {
        return "Il y a ${diff.inDays} j";
      } else if (diff.inHours >= 1) {
        return "Il y a ${diff.inHours} h";
      } else if (diff.inMinutes >= 1) {
        return "Il y a ${diff.inMinutes} min";
      } else {
        return "À l'instant";
      }
    } catch (e) {
      return "";
    }
  }

  void _shareVideo() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Lien de la vidéo copié !", style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFF7C4DFF),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Fonction pour formater les grands nombres
  String _formatCount(int count) {
    if (count < 1000) {
      return count.toString();
    } else if (count < 1000000) {
      double k = count / 1000.0;
      return '${k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1)}K';
    } else {
      double m = count / 1000000.0;
      return '${m.toStringAsFixed(m.truncateToDouble() == m ? 0 : 1)}M';
    }
  }

  void _goToAuth() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AuthScreen()),
    );
  }

  void _handleDoubleTap() {
    // Ajoute un retour haptique (vibration légère) pour simuler l'effet TikTok
    HapticFeedback.mediumImpact();

    // Déclenche l'affichage du coeur au centre
    setState(() => _showHeart = true);
    _heartController.forward(from: 0.0).then((_) {
      // On cache le coeur après un court délai une fois l'animation finie
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _showHeart = false);
      });
    });

    // Like automatique si ce n'est pas déjà fait
    if (!_isLiked) _toggleLike();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.feedVisible.removeListener(_handleFeedVisibleChanged);
    player.pause();
    player.dispose(); // Très important pour éviter les fuites de mémoire vive
    _heartController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1A2E),
      body: Stack(
        children: [
          // 1. Le Lecteur Vidéo plein écran (Ici, "Video" désigne bien le widget de media_kit)
          GestureDetector(
            onTap: () {
              player.playOrPause(); // Pause/Play au clic sur l'écran
            },
            onDoubleTap: _handleDoubleTap,
            child: SizedBox.expand(
              child: Video(
                controller: controller,
                controls: NoVideoControls, // On cache les boutons classiques
                fit: BoxFit.cover, // On s'assure que la vidéo couvre tout l'écran
              ),
            ),
          ),

          // Coeur animé au centre lors du double-clic
          if (_showHeart)
            IgnorePointer(
              child: Center(
                child: ScaleTransition(
                  scale: _heartAnimation,
                  child: const Icon(
                    Icons.favorite,
                    color: Colors.white,
                    size: 110,
                  ),
                ),
              ),
            ),

          if (widget.showBackButton)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.42),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          Positioned(
            left: 15,
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _openProfile,
                    child: Text(
                      '@${widget.video.username}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    widget.video.title,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  if (widget.video.description != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      widget.video.description!,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ]
                ],
              ),
            ),
          ),

          // 3. Les boutons d'interaction (à droite)
          Positioned(
            right: 15,
            bottom: 40,
            child: Column(
              children: [
                // Avatar auteur (cliquable)
                GestureDetector(
                  onTap: _openProfile,
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.white,
                    child: const CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.grey,
                      child: Icon(Icons.person, color: Colors.white, size: 20),
                    ),
                  ),
                ),
                const SizedBox(height: 25),
                
                _buildActionButton(
                  _isLiked ? Icons.favorite : Icons.favorite_border, 
                  _formatCount(_likesCount), 
                  _isLiked ? Colors.red : Colors.white,
                  onTap: _toggleLike,
                ),
                const SizedBox(height: 20),
                _buildActionButton(
                  Icons.comment, 
                  _formatCount(_commentsCount), 
                  Colors.white, 
                  onTap: _showCommentsBottomSheet
                ),
                const SizedBox(height: 20),
                _buildActionButton(
                  _isFavorited ? Icons.bookmark : Icons.bookmark_border, 
                  "Favoris", 
                  _isFavorited ? Colors.yellow : Colors.white,
                  onTap: _toggleFavorite,
                ),
                const SizedBox(height: 20),
                _buildActionButton(Icons.share, "Partager", Colors.white, onTap: _shareVideo),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF111B2D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}