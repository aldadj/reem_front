import 'session_manager.dart';

/// Mémorise, pendant la session, l'état like / favori de chaque vidéo.
///
/// Sans ça, quand on défile puis qu'on revient sur une vidéo, le lecteur est
/// reconstruit avec les anciennes données du fil (coeur non rouge, compteur
/// ancien). Ici on garde la dernière valeur connue, par utilisateur.
class VideoInteraction {
  const VideoInteraction({
    required this.liked,
    required this.favorited,
    required this.likesCount,
  });

  final bool liked;
  final bool favorited;
  final int likesCount;
}

class VideoInteractionStore {
  VideoInteractionStore._();

  static final Map<String, VideoInteraction> _items = {};

  static String _key(int videoId) {
    final userId = SessionManager().currentUser?['id'] ?? 'invite';
    return '$userId:$videoId';
  }

  static VideoInteraction? read(int videoId) => _items[_key(videoId)];

  static void write(
    int videoId, {
    required bool liked,
    required bool favorited,
    required int likesCount,
  }) {
    _items[_key(videoId)] = VideoInteraction(
      liked: liked,
      favorited: favorited,
      likesCount: likesCount < 0 ? 0 : likesCount,
    );
  }
}
