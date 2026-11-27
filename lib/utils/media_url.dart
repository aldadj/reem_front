import '../services/auth_service.dart';

/// Rend absolue l'adresse d'une image renvoyée par l'API
/// (Cloudinary : déjà complète ; ancien stockage : chemin relatif).
String? absoluteMediaUrl(String? path) {
  if (path == null || path.trim().isEmpty) return null;
  if (path.startsWith('http')) return path;
  final base = AuthService.baseUrl.replaceFirst(RegExp(r'/api$'), '');
  return '$base${path.startsWith('/') ? '' : '/'}$path';
}

/// Miniature d'une vidéo (JSON de l'API) : celle enregistrée, sinon celle générée par Cloudinary.
String? videoThumbnailUrl(Map<String, dynamic> video) {
  final raw = (video['thumbnail_path'] ?? '').toString();
  if (raw.isNotEmpty) return absoluteMediaUrl(raw);

  final path = (video['video_path'] ?? '').toString();
  if (path.contains('/video/upload/')) {
    return path
        .replaceFirst('/video/upload/', '/video/upload/so_0,w_480,h_800,c_fill,q_auto/')
        .replaceFirst(RegExp(r'\.(mp4|mov|avi|mkv|webm)$', caseSensitive: false), '.jpg');
  }
  return null;
}
