import '../services/auth_service.dart';
import '../utils/platform_helper.dart';

class Video {
  final int id;
  final String title;
  final String? description;
  final String videoUrl;
  final String username;
  final int authorId;
  final String? authorProfilePhotoUrl; // NOUVEAU
  final int likesCount;
  final int commentsCount;
  final bool isLiked;
  final bool isFavorited;
  final bool isAuthorFollowed; // l'utilisateur connecté suit-il l'auteur ?

  Video({
    required this.id,
    required this.title,
    this.description,
    required this.videoUrl,
    required this.username,
    required this.authorId,
    this.authorProfilePhotoUrl, // NOUVEAU
    required this.likesCount,
    required this.commentsCount,
    required this.isLiked,
    required this.isFavorited,
    this.isAuthorFollowed = false,
  });

  // Convertit le JSON de Laravel en objet Dart
  factory Video.fromJson(Map<String, dynamic> json) {
    String url = json['video_url'] ?? json['video_path'] ?? '';
    if (isAndroidPlatform && (url.contains('localhost') || url.contains('127.0.0.1'))) {
      url = url.replaceAll('localhost', '10.0.2.2').replaceAll('127.0.0.1', '10.0.2.2');
    }
    if (url.isNotEmpty && !url.startsWith('http')) {
      final host = AuthService.baseUrl.replaceFirst(RegExp(r'/api$'), '');
      url = '$host${url.startsWith('/') ? '' : '/'}$url';
    }

    return Video(
      id: json['id'],
      title: json['title'] ?? '',
      description: json['description'],
      videoUrl: url,
      username: json['user']?['name'] ?? 'Anonyme',
      authorId: json['user']?['id'] ?? 0,
      authorProfilePhotoUrl: json['user']?['profile_photo_path'], // NOUVEAU
      likesCount: json['likes_count'] ?? 0,
      commentsCount: json['comments_count'] ?? 0,
      isLiked: json['liked_by_user'] ?? false,
      isFavorited: json['favorited_by_user'] ?? false,
      isAuthorFollowed: json['author_is_followed'] == true,
    );
  }
}