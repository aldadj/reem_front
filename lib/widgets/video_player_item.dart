import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import '../services/session_manager.dart';
import '../services/auth_service.dart';
import '../services/video_interaction_store.dart';
import '../services/video_playback_coordinator.dart';
import '../screens/auth_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/profile_screen.dart';
import '../models/video.dart' as app_models; // On ajoute l'alias "app_models" ici
import 'video_comments_panel.dart';

class VideoPlayerItem extends StatefulWidget {
  final app_models.Video video;
  final ValueNotifier<bool> feedVisible;
  final ValueNotifier<int>? visibleVideoIndex;
  final int? itemIndex;
  final VoidCallback? onAutoNext;
  final bool showBackButton;

  const VideoPlayerItem({
    Key? key,
    required this.video,
    required this.feedVisible,
    this.visibleVideoIndex,
    this.itemIndex,
    this.onAutoNext,
    this.showBackButton = true,
  }) : super(key: key);

  @override
  State<VideoPlayerItem> createState() => _VideoPlayerItemState();
}

class _VideoPlayerItemState extends State<VideoPlayerItem> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Player player;
  late final VideoController controller;
  final Object _playerId = Object();

  // Sur le web, le mode muet automatique est géré dans web/index.html
  // (voir le script d'autoplay) : ici on garde toujours le volume normal.
  bool _userPaused = false; // l'utilisateur a mis cette vidéo en pause lui-même
  double get _effectiveVolume => _volume;

  // État local pour TikTok feel
  bool _isLiked = false;
  bool _isFavorited = false;
  bool _isPlaying = false;
  bool _showCommentsPanel = false;
  bool _autoScroll = false;
  bool _showVolumeSlider = false;
  bool _isDownloading = false;
  double _playbackRate = 1.0;
  double _volume = 100.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late int _likesCount;
  late int _commentsCount;
  final SessionManager _sessionManager = SessionManager();

  // Animation du coeur au centre
  late final AnimationController _heartController;
  late final Animation<double> _heartAnimation;
  bool _showHeart = false;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _completedSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    player = Player();
    controller = VideoController(player);
    VideoPlaybackCoordinator.register(_playerId, player.pause);

    widget.feedVisible.addListener(_handleFeedVisibleChanged);
    widget.visibleVideoIndex?.addListener(_handleFeedVisibleChanged);
    _positionSubscription = player.stream.position.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _durationSubscription = player.stream.duration.listen((duration) {
      if (!mounted) return;
      setState(() => _duration = duration);
      // Filet de sécurité : la vidéo est chargée, elle doit jouer si elle est visible.
      if (duration > Duration.zero && _shouldPlay && !_isPlaying && !_userPaused) {
        _activatePlayback();
      }
    });
    _playingSubscription = player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
    _completedSubscription = player.stream.completed.listen((completed) {
      if (completed && _autoScroll && widget.onAutoNext != null) {
        widget.onAutoNext!();
      }
    });

    _isLiked = widget.video.isLiked;
    _isFavorited = widget.video.isFavorited;
    _likesCount = widget.video.likesCount;
    _commentsCount = widget.video.commentsCount;
    _applyStoredInteraction();

    _openVideo(widget.video.videoUrl);

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
  void didUpdateWidget(covariant VideoPlayerItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.feedVisible != widget.feedVisible) {
      oldWidget.feedVisible.removeListener(_handleFeedVisibleChanged);
      widget.feedVisible.addListener(_handleFeedVisibleChanged);
    }
    if (oldWidget.visibleVideoIndex != widget.visibleVideoIndex) {
      oldWidget.visibleVideoIndex?.removeListener(_handleFeedVisibleChanged);
      widget.visibleVideoIndex?.addListener(_handleFeedVisibleChanged);
    }
    if (oldWidget.video.id != widget.video.id || oldWidget.video.videoUrl != widget.video.videoUrl) {
      _isLiked = widget.video.isLiked;
      _isFavorited = widget.video.isFavorited;
      _likesCount = widget.video.likesCount;
      _commentsCount = widget.video.commentsCount;
      _applyStoredInteraction();
      _openVideo(widget.video.videoUrl);
    } else if (oldWidget.feedVisible != widget.feedVisible ||
        oldWidget.visibleVideoIndex != widget.visibleVideoIndex) {
      _handleFeedVisibleChanged();
    }
  }

  bool get _shouldPlay => widget.feedVisible.value &&
      (widget.visibleVideoIndex == null || widget.itemIndex == widget.visibleVideoIndex!.value);

  Future<void> _openVideo(String url) async {
    try {
      await player.open(Media(url), play: false);
      await player.setPlaylistMode(PlaylistMode.single);
      await player.setVolume(_effectiveVolume);
    } catch (e) {
      debugPrint('[Reem autoplay] ouverture impossible ($url) : $e');
      return;
    }
    if (!mounted) return;
    if (_shouldPlay && !_userPaused) await _activatePlayback();
  }

  Future<void> _activatePlayback() => VideoPlaybackCoordinator.activate(_playerId, () async {
        await player.setVolume(_effectiveVolume);
        await player.play();
      });

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      _userPaused = true;
      await player.pause();
      await VideoPlaybackCoordinator.deactivate(_playerId);
    } else {
      _userPaused = false;
      await _activatePlayback();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      player.pause();
    } else if (state == AppLifecycleState.resumed) {
      if (_shouldPlay && !_userPaused) {
        _activatePlayback();
      } else {
        player.pause();
      }
    }
  }

  void _handleFeedVisibleChanged() {
    if (!mounted) return;
    if (_shouldPlay) {
      if (!_userPaused) _activatePlayback();
    } else {
      _userPaused = false; // quand on revient sur cette vidéo, elle repart seule
      player.pause().then((_) => VideoPlaybackCoordinator.deactivate(_playerId));
    }
  }

  void _toggleCommentsPanel() => setState(() => _showCommentsPanel = !_showCommentsPanel);

  Future<void> _downloadVideo() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      final response = await http.get(Uri.parse(widget.video.videoUrl));
      if (response.statusCode != 200) throw Exception('Téléchargement impossible.');
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer la vidéo',
        fileName: 'reem_video_${widget.video.id}.mp4',
        type: FileType.video,
        bytes: response.bodyBytes,
      );
      if (!mounted) return;
      if (savedPath != null || kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vidéo téléchargée.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur de téléchargement : $error')));
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showMobilePlaybackSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.48,
        minChildSize: 0.32,
        maxChildSize: 0.78,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF202124),
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Paramètres de lecture', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Défilement automatique', style: TextStyle(color: Colors.white)),
                value: _autoScroll,
                activeTrackColor: Colors.redAccent,
                onChanged: (value) => setState(() => _autoScroll = value),
              ),
              const Text('Vitesse', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [0.75, 1.0, 1.25, 1.5, 2.0].map((rate) {
                  final label = rate == 1.0 ? '1.0x' : '${rate}x';
                  return ChoiceChip(
                    label: Text(label),
                    selected: _playbackRate == rate,
                    onSelected: (_) {
                      setState(() => _playbackRate = rate);
                      player.setRate(rate);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(_volume == 0 ? Icons.volume_off : Icons.volume_up, color: Colors.white70),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: 100,
                      value: _volume,
                      activeColor: Colors.white,
                      onChanged: (value) {
                        setState(() => _volume = value);
                        player.setVolume(value);
                      },
                    ),
                  ),
                  Text('${_volume.round()}%', style: const TextStyle(color: Colors.white70)),
                ],
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _isDownloading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_outlined, color: Colors.white),
                title: const Text('Télécharger la vidéo', style: TextStyle(color: Colors.white)),
                onTap: _isDownloading ? null : _downloadVideo,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatPlaybackTime(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildPlaybackBar() {
    final durationMs = _duration.inMilliseconds;
    final positionMs = _position.inMilliseconds.clamp(0, durationMs > 0 ? durationMs : 0);
    final rateLabel = switch (_playbackRate) {
      0.75 => '0.75x',
      1.25 => '1.25x',
      1.5 => '1.5x',
      2.0 => '2.0x',
      _ => '1.0x',
    };
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.52),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: _isPlaying ? 'Pause' : 'Lecture',
                    onPressed: _togglePlayback,
                    icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 24),
                  ),
                  Text(_formatPlaybackTime(_position), style: const TextStyle(color: Colors.white, fontSize: 11)),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: durationMs > 0 ? durationMs.toDouble() : 1,
                      value: positionMs.toDouble(),
                      activeColor: Colors.redAccent,
                      inactiveColor: Colors.white30,
                      onChanged: durationMs <= 0 ? null : (value) => player.seek(Duration(milliseconds: value.round())),
                    ),
                  ),
                  Text(_formatPlaybackTime(_duration), style: const TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
              if (MediaQuery.sizeOf(context).width >= 768)
                Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Tooltip(
                          message: _autoScroll ? 'Défilement automatique activé' : 'Défilement automatique désactivé',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.skip_next_rounded, color: Colors.white70, size: 17),
                              Switch.adaptive(
                                value: _autoScroll,
                                activeTrackColor: Colors.redAccent,
                                onChanged: (value) => setState(() => _autoScroll = value),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<double>(
                          tooltip: 'Vitesse de lecture',
                          initialValue: _playbackRate,
                          onSelected: (value) {
                            setState(() => _playbackRate = value);
                            player.setRate(value);
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 0.75, child: Text('0.75x')),
                            PopupMenuItem(value: 1.0, child: Text('1.0x · Normal')),
                            PopupMenuItem(value: 1.25, child: Text('1.25x')),
                            PopupMenuItem(value: 1.5, child: Text('1.5x')),
                            PopupMenuItem(value: 2.0, child: Text('2.0x')),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Text(rateLabel, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: _showVolumeSlider ? 'Masquer le volume' : 'Régler le volume',
                          onPressed: () => setState(() => _showVolumeSlider = !_showVolumeSlider),
                          icon: Icon(_volume == 0 ? Icons.volume_off : Icons.volume_up, color: Colors.white, size: 19),
                        ),
                        if (_showVolumeSlider)
                          SizedBox(
                            width: 84,
                            child: Slider(
                              min: 0,
                              max: 100,
                              value: _volume,
                              activeColor: Colors.white,
                              onChanged: (value) {
                                setState(() => _volume = value);
                                player.setVolume(value);
                              },
                            ),
                          ),
                        IconButton(
                          tooltip: 'Télécharger la vidéo',
                          visualDensity: VisualDensity.compact,
                          onPressed: _isDownloading ? null : _downloadVideo,
                          icon: _isDownloading
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.download_outlined, color: Colors.white, size: 19),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ),
    );
  }

  // Reprend la dernière valeur connue (like / favori / compteur) de cette vidéo
  void _applyStoredInteraction() {
    final stored = VideoInteractionStore.read(widget.video.id);
    if (stored == null) return;
    _isLiked = stored.liked;
    _isFavorited = stored.favorited;
    _likesCount = stored.likesCount;
  }

  void _saveInteraction(int videoId) {
    VideoInteractionStore.write(
      videoId,
      liked: _isLiked,
      favorited: _isFavorited,
      likesCount: _likesCount,
    );
  }

  Future<void> _toggleLike() async {
    if (!_sessionManager.isAuthenticated) {
      _goToAuth();
      return;
    }

    final videoId = widget.video.id;
    void flip() {
      _isLiked = !_isLiked;
      _likesCount += _isLiked ? 1 : -1;
      if (_likesCount < 0) _likesCount = 0;
    }

    setState(flip);
    _saveInteraction(videoId);

    var success = false;
    try {
      final response = await http.post(
        Uri.parse("${AuthService.baseUrl}/videos/$videoId/like"),
        headers: {
          'Authorization': 'Bearer ${_sessionManager.authToken}',
          'Accept': 'application/json',
        },
      );
      success = response.statusCode == 200;
      if (success) {
        try {
          final data = jsonDecode(response.body);
          if (data is Map) {
            // On se cale sur la réponse du serveur
            if (data['liked'] != null) _isLiked = data['liked'] == true;
            if (data['likes_count'] is num) {
              _likesCount = (data['likes_count'] as num).toInt();
            }
            if (mounted) setState(() {});
            _saveInteraction(videoId);
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Erreur Like: $e');
    }

    if (!success) {
      // Rollback si erreur serveur / réseau
      if (mounted) {
        setState(flip);
      } else {
        flip();
      }
      _saveInteraction(videoId);
    }
  }

  Future<void> _toggleFavorite() async {
    if (!_sessionManager.isAuthenticated) {
      _goToAuth();
      return;
    }

    final videoId = widget.video.id;
    setState(() => _isFavorited = !_isFavorited);
    _saveInteraction(videoId);

    var success = false;
    try {
      final response = await http.post(
        Uri.parse("${AuthService.baseUrl}/videos/$videoId/favorite"),
        headers: {
          'Authorization': 'Bearer ${_sessionManager.authToken}',
          'Accept': 'application/json',
        },
      );
      success = response.statusCode == 200;
      if (success) {
        try {
          final data = jsonDecode(response.body);
          if (data is Map && data['favorited'] != null) {
            _isFavorited = data['favorited'] == true;
            if (mounted) setState(() {});
            _saveInteraction(videoId);
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint("Erreur Favoris: $e");
    }

    if (!success) {
      if (mounted) {
        setState(() => _isFavorited = !_isFavorited);
      } else {
        _isFavorited = !_isFavorited;
      }
      _saveInteraction(videoId);
    }
  }

  void _openProfile() {
    if (widget.video.authorId == 0) return;
    final wasVisible = widget.feedVisible.value;
    widget.feedVisible.value = false;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(userId: widget.video.authorId),
      ),
    ).then((_) {
      if (mounted && wasVisible) widget.feedVisible.value = true;
    });
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

  Future<void> _shareVideo() async {
    final link = widget.video.videoUrl;
    final shareText = '${widget.video.title}\n$link';
    if (!_sessionManager.isAuthenticated) {
      await SharePlus.instance.share(ShareParams(text: shareText, subject: widget.video.title));
      return;
    }

    List<dynamic> friends = [];
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/users/following'),
        headers: {
          'Authorization': 'Bearer ${_sessionManager.authToken}',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) friends = jsonDecode(response.body) as List<dynamic>;
    } catch (e) {
      debugPrint('Impossible de charger les amis pour le partage : $e');
    }
    if (!mounted) return;

    final selectedIds = <int>{};
    var isSending = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF171717),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Partager la vidéo', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                if (friends.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('Aucun ami suivi pour le moment.', style: TextStyle(color: Colors.white60)),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.32),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: friends.length,
                      itemBuilder: (context, index) {
                        final friend = friends[index] as Map<String, dynamic>;
                        final id = friend['id'] as int;
                        final selected = selectedIds.contains(id);
                        return CheckboxListTile(
                          value: selected,
                          activeColor: Colors.redAccent,
                          contentPadding: EdgeInsets.zero,
                          title: Text(friend['name']?.toString() ?? 'Utilisateur', style: const TextStyle(color: Colors.white)),
                          secondary: CircleAvatar(
                            backgroundColor: Colors.white12,
                            child: Text((friend['name']?.toString().isNotEmpty ?? false) ? friend['name'].toString()[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
                          ),
                          onChanged: (value) => setSheetState(() {
                            if (value == true) {
                              selectedIds.add(id);
                            } else {
                              selectedIds.remove(id);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                const Divider(color: Colors.white24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: link));
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('Lien copié.')));
                          }
                        },
                        icon: const Icon(Icons.link),
                        label: const Text('Copier le lien'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: selectedIds.isEmpty || isSending
                            ? null
                            : () async {
                                setSheetState(() => isSending = true);
                                var sentCount = 0;
                                for (final id in selectedIds) {
                                  try {
                                    final conversationResponse = await http.post(
                                      Uri.parse('${AuthService.baseUrl}/conversations'),
                                      headers: {
                                        'Authorization': 'Bearer ${_sessionManager.authToken}',
                                        'Content-Type': 'application/json',
                                        'Accept': 'application/json',
                                      },
                                      body: jsonEncode({'other_user_id': id}),
                                    );
                                    if (conversationResponse.statusCode != 200) continue;
                                    final conversationId = jsonDecode(conversationResponse.body)['id'];
                                    final messageResponse = await http.post(
                                      Uri.parse('${AuthService.baseUrl}/conversations/$conversationId/messages'),
                                      headers: {
                                        'Authorization': 'Bearer ${_sessionManager.authToken}',
                                        'Content-Type': 'application/json',
                                        'Accept': 'application/json',
                                      },
                                      body: jsonEncode({
                                        'body': 'REEM_VIDEO:${jsonEncode({
                                          'id': widget.video.id,
                                          'title': widget.video.title,
                                          'description': widget.video.description,
                                          'video_url': link,
                                          'username': widget.video.username,
                                          'author_id': widget.video.authorId,
                                          'likes_count': widget.video.likesCount,
                                          'comments_count': widget.video.commentsCount,
                                          'is_liked': false,
                                          'is_favorited': false,
                                        })}',
                                      }),
                                    );
                                    if (messageResponse.statusCode == 201) sentCount++;
                                  } catch (e) {
                                    debugPrint('Échec du partage avec $id : $e');
                                  }
                                }
                                if (sheetContext.mounted) Navigator.pop(sheetContext);
                                if (mounted) {
                                  ScaffoldMessenger.of(this.context).showSnackBar(
                                    SnackBar(content: Text(sentCount > 0 ? 'Vidéo partagée avec $sentCount ami(s).' : 'Impossible d’envoyer la vidéo.')),
                                  );
                                }
                              },
                        icon: isSending
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send),
                        label: const Text('Envoyer'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () async {
                      await SharePlus.instance.share(ShareParams(text: shareText, subject: widget.video.title));
                    },
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Autres applications'),
                  ),
                ),
              ],
            ),
          ),
        ),
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
    final wasVisible = widget.feedVisible.value;
    widget.feedVisible.value = false;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AuthScreen()),
    ).then((_) {
      if (mounted && wasVisible) widget.feedVisible.value = true;
    });
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
    widget.visibleVideoIndex?.removeListener(_handleFeedVisibleChanged);
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playingSubscription?.cancel();
    _completedSubscription?.cancel();
    player.pause();
    VideoPlaybackCoordinator.unregister(_playerId);
    player.dispose(); // Très important pour éviter les fuites de mémoire vive
    _heartController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isTabletOrDesktop = constraints.maxWidth >= 768;
          final commentsPanel = VideoCommentsPanel(
            videoId: widget.video.id,
            onClose: _toggleCommentsPanel,
            onCountChanged: (count) {
              if (mounted && count != _commentsCount) setState(() => _commentsCount = count);
            },
          );

          if (isTabletOrDesktop) {
            return Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _buildVideoSurface()),
                      _buildPlaybackBar(),
                    ],
                  ),
                ),
                if (_showCommentsPanel)
                  SizedBox(width: 360, child: commentsPanel),
              ],
            );
          }

          final commentsHeight = math.min(
            constraints.maxHeight * 0.52,
            math.max(180.0, constraints.maxHeight * 0.38),
          );
          return Column(
            children: [
              Expanded(child: _buildVideoSurface()),
              _buildPlaybackBar(),
              if (_showCommentsPanel)
                SizedBox(height: commentsHeight, child: commentsPanel),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVideoSurface() {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: _togglePlayback,
          onDoubleTap: _handleDoubleTap,
          onLongPress: MediaQuery.sizeOf(context).width < 768 ? _showMobilePlaybackSettings : null,
          child: Video(
            controller: controller,
            controls: NoVideoControls,
            fit: BoxFit.contain,
          ),
        ),
        if (!_isPlaying)
          IgnorePointer(
            child: Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white.withValues(alpha: 0.62),
                size: 74,
              ),
            ),
          ),
        if (_showHeart)
          IgnorePointer(
            child: Center(
              child: ScaleTransition(
                scale: _heartAnimation,
                child: const Icon(Icons.favorite, color: Colors.white, size: 110),
              ),
            ),
          ),
        if (widget.showBackButton)
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: IconButton(
                tooltip: 'Retour',
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        Positioned(
          left: 14,
          bottom: 14,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.62),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _openProfile,
                    child: Text('@${widget.video.username}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 3),
                  Text(widget.video.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                  if (widget.video.description != null)
                    Text(widget.video.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 8,
          bottom: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _openProfile,
                child: const CircleAvatar(
                  radius: 21,
                  backgroundColor: Colors.white,
                  child: CircleAvatar(radius: 19, backgroundColor: Colors.grey, child: Icon(Icons.person, color: Colors.white, size: 20)),
                ),
              ),
              const SizedBox(height: 10),
              _buildActionButton(_isLiked ? Icons.favorite : Icons.favorite_border, _formatCount(_likesCount), _isLiked ? Colors.red : Colors.white, onTap: _toggleLike),
              _buildActionButton(Icons.comment, _formatCount(_commentsCount), Colors.white, onTap: _toggleCommentsPanel),
              _buildActionButton(_isFavorited ? Icons.bookmark : Icons.bookmark_border, 'Favoris', _isFavorited ? Colors.yellow : Colors.white, onTap: _toggleFavorite),
              _buildActionButton(Icons.share, 'Partager', Colors.white, onTap: _shareVideo),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
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