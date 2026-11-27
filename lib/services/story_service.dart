import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'session_manager.dart';

/// Une story (photo ou vidéo visible 24 h).
class StoryItem {
  StoryItem({
    required this.id,
    required this.isVideo,
    required this.mediaUrl,
    this.thumbnailUrl,
    this.caption,
    this.createdAt,
    this.expiresAt,
    this.viewed = false,
    this.viewsCount,
  });

  final int id;
  final bool isVideo;
  final String mediaUrl;
  final String? thumbnailUrl;
  final String? caption;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  bool viewed;
  int? viewsCount; // renseigné seulement pour mes propres stories

  factory StoryItem.fromJson(Map<String, dynamic> json) {
    return StoryItem(
      id: int.parse('${json['id']}'),
      isVideo: json['media_type'] == 'video',
      mediaUrl: '${json['media_url']}',
      thumbnailUrl: json['thumbnail_url']?.toString(),
      caption: json['caption']?.toString(),
      createdAt: DateTime.tryParse('${json['created_at']}')?.toLocal(),
      expiresAt: DateTime.tryParse('${json['expires_at']}')?.toLocal(),
      viewed: json['viewed'] == true,
      viewsCount: json['views_count'] == null ? null : int.tryParse('${json['views_count']}'),
    );
  }
}

/// Les stories d'une personne.
class StoryGroup {
  StoryGroup({required this.user, required this.isMe, required this.stories});

  final Map<String, dynamic> user;
  final bool isMe;
  final List<StoryItem> stories;

  int get userId => int.tryParse('${user['id']}') ?? -1;
  String get name => '${user['name'] ?? ''}';
  String? get photo => user['profile_photo_path']?.toString();
  bool get hasUnseen => stories.any((story) => !story.viewed);

  factory StoryGroup.fromJson(Map<String, dynamic> json) {
    return StoryGroup(
      user: Map<String, dynamic>.from(json['user'] as Map),
      isMe: json['is_me'] == true,
      stories: (json['stories'] as List)
          .map((item) => StoryItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }
}

class StoryService {
  final SessionManager _session = SessionManager();

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${_session.authToken}',
      };

  String get _base => AuthService.baseUrl;

  Future<List<StoryGroup>> fetchStories() async {
    if (!_session.isAuthenticated) return [];
    try {
      final response = await http.get(Uri.parse('$_base/stories'), headers: _headers);
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as List;
      return data
          .map((group) => StoryGroup.fromJson(Map<String, dynamic>.from(group as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Publie une story. Retourne null si c'est publié, sinon le message d'erreur.
  Future<String?> create({
    String? path,
    Uint8List? bytes,
    String? fileName,
    String? caption,
  }) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$_base/stories'))
        ..headers.addAll(_headers);
      if (caption != null && caption.trim().isNotEmpty) request.fields['caption'] = caption.trim();

      if (bytes != null) {
        request.files.add(http.MultipartFile.fromBytes('media', bytes, filename: fileName ?? 'story.jpg'));
      } else if (path != null) {
        request.files.add(await http.MultipartFile.fromPath('media', path));
      } else {
        return 'Aucun fichier à envoyer.';
      }

      final response = await http.Response.fromStream(await request.send());
      if (response.statusCode == 201) return null;

      final body = jsonDecode(response.body);
      if (body is Map) {
        final errors = body['errors'];
        if (errors is Map && errors.isNotEmpty) {
          final first = errors.values.first;
          if (first is List && first.isNotEmpty) return first.first.toString();
        }
        if (body['message'] != null) return body['message'].toString();
      }
      return 'Impossible de publier la story.';
    } catch (_) {
      return 'Impossible de publier la story. Vérifie ta connexion.';
    }
  }

  Future<bool> delete(int id) async {
    try {
      final response = await http.delete(Uri.parse('$_base/stories/$id'), headers: _headers);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> markViewed(int id) async {
    try {
      await http.post(Uri.parse('$_base/stories/$id/view'), headers: _headers);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> viewers(int id) async {
    try {
      final response = await http.get(Uri.parse('$_base/stories/$id/viewers'), headers: _headers);
      if (response.statusCode != 200) return [];
      return (jsonDecode(response.body) as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
