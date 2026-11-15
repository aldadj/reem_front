import '../services/auth_service.dart';

/// Rend absolue l'adresse d'une image renvoyée par l'API
/// (Cloudinary : déjà complète ; ancien stockage : chemin relatif).
String? absoluteMediaUrl(String? path) {
  if (path == null || path.trim().isEmpty) return null;
  if (path.startsWith('http')) return path;
  final base = AuthService.baseUrl.replaceFirst(RegExp(r'/api$'), '');
  return '$base${path.startsWith('/') ? '' : '/'}$path';
}
