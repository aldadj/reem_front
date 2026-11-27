import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/story_service.dart';
import '../theme/reem_theme.dart';

/// Aperçu d'une photo ou d'une vidéo avant de la publier en story (légende facultative).
/// Se ferme avec `true` quand la story est publiée.
class StoryPreviewScreen extends StatefulWidget {
  const StoryPreviewScreen({
    super.key,
    this.path,
    this.bytes,
    this.fileName,
    required this.isVideo,
  });

  final String? path; // mobile : chemin du fichier
  final Uint8List? bytes; // web : contenu du fichier
  final String? fileName;
  final bool isVideo;

  @override
  State<StoryPreviewScreen> createState() => _StoryPreviewScreenState();
}

class _StoryPreviewScreenState extends State<StoryPreviewScreen> {
  final TextEditingController _caption = TextEditingController();
  final StoryService _service = StoryService();

  Player? _player;
  VideoController? _videoController;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo && widget.path != null && !kIsWeb) {
      final player = Player();
      _player = player;
      _videoController = VideoController(player);
      player.setPlaylistMode(PlaylistMode.loop);
      player.open(Media(widget.path!), play: true);
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (_posting) return;
    setState(() => _posting = true);

    final error = await _service.create(
      path: widget.bytes == null ? widget.path : null,
      bytes: widget.bytes,
      fileName: widget.fileName,
      caption: _caption.text,
    );

    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _posting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Widget _preview() {
    if (widget.isVideo) {
      final controller = _videoController;
      if (controller != null) {
        return Video(controller: controller, controls: NoVideoControls, fit: BoxFit.contain);
      }
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_rounded, color: Colors.white70, size: 64),
            SizedBox(height: 10),
            Text('Vidéo prête à être publiée', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }
    if (widget.bytes != null) return Image.memory(widget.bytes!, fit: BoxFit.contain);
    if (widget.path != null && !kIsWeb) return Image.file(File(widget.path!), fit: BoxFit.contain);
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ReemTheme.dark(),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          resizeToAvoidBottomInset: true,
          body: Stack(
            fit: StackFit.expand,
            children: [
              _preview(),
              // Voile sombre en haut et en bas : boutons et légende restent lisibles sur toute image
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.45),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.6),
                      ],
                      stops: const [0, 0.22, 0.6, 1],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28, shadows: reemTextShadow),
                        onPressed: _posting ? null : () => Navigator.pop(context),
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _caption,
                        maxLength: 200,
                        maxLines: 2,
                        minLines: 1,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Ajouter une légende…',
                          hintStyle: const TextStyle(color: Colors.white70),
                          counterStyle: const TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: Colors.black54,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Ta story reste visible 24 h. Tu peux la supprimer à tout moment.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 12.5, shadows: reemTextShadow),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _posting ? null : _publish,
                          icon: _posting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.auto_awesome_rounded, size: 20),
                          label: Text(_posting ? 'Publication…' : 'Publier la story'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            backgroundColor: ReemColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
