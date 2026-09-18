import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:reem_front/models/video.dart' as app_models;

class VideoTile extends StatefulWidget {
  final app_models.Video video;
  final Player player;
  final bool isCurrent;

  const VideoTile({
    super.key,
    required this.video,
    required this.player,
    required this.isCurrent,
  });

  @override
  State<VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<VideoTile> {
  late final VideoController _videoController;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _videoController = VideoController(widget.player);
    // On attend que le lecteur soit prêt (il est peut-être déjà en cours de chargement)
    widget.player.stream.completed.first.then((completed) {
      if (mounted && completed) {
        setState(() {
          _isInitialized = true;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant VideoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCurrent && !oldWidget.isCurrent) {
      widget.player.play();
    } else if (!widget.isCurrent && oldWidget.isCurrent) {
      widget.player.pause();
    }
  }

  // GÈRE LA PAUSE ET LA REPRISE AU CLIC SUR LA VIDÉO
  void _togglePlay() async {
    if (!_isInitialized) return;
    await widget.player.playOrPause();
  }

  @override
  void dispose() {
    // La gestion de la suppression du player se fait maintenant dans le FeedScreen
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. LE LECTEUR VIDÉO (Prend toute la surface disponible et gère le clic)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque, // Capte les clics même sur les zones transparentes
              onTap: _togglePlay,
              child: _isInitialized
                  ? Video(controller: _videoController, fit: BoxFit.cover)
                  : const Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
          ),

          // 2. LOGO DE PAUSE AU CENTRE (Apparaît si la vidéo est sur pause)
          if (_isInitialized && !widget.player.state.playing)
            IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow, size: 45, color: Colors.white),
                ),
              ),
            ),

          // 3. BARRE LATÉRALE DROITE (Boutons d'interactions)
          Positioned(
            right: 15,
            bottom: 40, // Redescendu car la vidéo s'arrête au-dessus de la barre de navigation
            child: Column(
              children: [
                // Avatar Auteur
                Stack(
                  alignment: Alignment.bottomCenter,
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                        color: Colors.grey[800],
                      ),
                      child: const Icon(Icons.person, color: Colors.white, size: 30),
                    ),
                    Positioned(
                      bottom: -8,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.add, color: Colors.white, size: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                _buildActionButton(Icons.favorite, _formatCount(widget.video.likesCount), Colors.red),
                const SizedBox(height: 18),
                _buildActionButton(Icons.comment, _formatCount(widget.video.commentsCount), Colors.white),
                const SizedBox(height: 18),
                _buildActionButton(Icons.bookmark, '89', Colors.amber), // Note: Le nombre de favoris n'est pas dans le modèle Video actuel.
                const SizedBox(height: 18),
                _buildActionButton(Icons.share, 'Partager', Colors.white),
              ],
            ),
          ),

          // 4. INFOS DU REEL (En bas à gauche)
          Positioned(
            left: 15,
            bottom: 30, // Ajusté également pour s'aligner proprement avec le bas de la vidéo
            right: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '@${widget.video.username}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // NOUVEAU : Fonction pour formater les nombres (ex: 12500 -> 12.5K)
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


  Widget _buildActionButton(IconData icon, String label, Color iconColor) {
    return Column(
      children: [
        Container(
          width: 45,
          height: 45,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(icon, color: iconColor, size: 24),
            onPressed: () {
              print("Clic sur le bouton : $label");
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            shadows: [Shadow(blurRadius: 2, color: Colors.black)],
          ),
        ),
      ],
    );
  }
}