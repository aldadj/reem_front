import 'package:flutter/material.dart';

import '../models/video.dart' as app_models;
import '../services/inbox_service.dart';
import '../theme/reem_theme.dart';
import '../widgets/video_player_item.dart';

/// Ouvre une vidéo précise, par exemple depuis une notification.
/// Avec [openComments], le panneau de commentaires s'ouvre tout de suite ;
/// avec [highlightCommentId], ce commentaire est mis en évidence.
class VideoViewerScreen extends StatefulWidget {
  const VideoViewerScreen({
    super.key,
    required this.videoId,
    this.openComments = false,
    this.highlightCommentId,
  });

  final int videoId;
  final bool openComments;
  final int? highlightCommentId;

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  final ValueNotifier<bool> _visible = ValueNotifier<bool>(true);
  late final Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = InboxService().fetchVideo(widget.videoId);
  }

  @override
  void dispose() {
    _visible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data == null) {
            return SafeArea(
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.videocam_off_outlined, color: ReemColors.textMuted, size: 64),
                          SizedBox(height: 16),
                          Text(
                            'Cette vidéo n’est plus disponible.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return VideoPlayerItem(
            video: app_models.Video.fromJson(data),
            feedVisible: _visible,
            showBackButton: true,
            openCommentsOnStart: widget.openComments,
            highlightCommentId: widget.highlightCommentId,
          );
        },
      ),
    );
  }
}
