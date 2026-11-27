import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/video.dart' as app_models;
import 'auth_service.dart';
import 'session_manager.dart';

/// Notifications, discussions et ouverture d'une vidéo précise.
class InboxService {
  final SessionManager _session = SessionManager();

  Map<String, String> _headers({bool json = false}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if (_session.isAuthenticated) 'Authorization': 'Bearer ${_session.authToken}',
      };

  String get _base => AuthService.baseUrl;

  Future<List<dynamic>> fetchNotifications() async {
    try {
      final response = await http.get(Uri.parse('$_base/notifications'), headers: _headers());
      if (response.statusCode == 200) return jsonDecode(response.body) as List<dynamic>;
    } catch (_) {}
    return [];
  }

  Future<bool> markRead(int id) async {
    try {
      final r = await http.post(Uri.parse('$_base/notifications/$id/read'), headers: _headers());
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> markAllRead() async {
    try {
      final r = await http.post(Uri.parse('$_base/notifications/read-all'), headers: _headers());
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteNotification(int id) async {
    try {
      final r = await http.delete(Uri.parse('$_base/notifications/$id'), headers: _headers());
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> clearNotifications() async {
    try {
      final r = await http.delete(Uri.parse('$_base/notifications'), headers: _headers());
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<dynamic>> fetchConversations() async {
    try {
      final response = await http.get(Uri.parse('$_base/conversations'), headers: _headers());
      if (response.statusCode == 200) return jsonDecode(response.body) as List<dynamic>;
    } catch (_) {}
    return [];
  }

  Future<bool> deleteConversation(int id) async {
    try {
      final r = await http.delete(Uri.parse('$_base/conversations/$id'), headers: _headers());
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Supprime un de mes messages (pour tout le monde).
  Future<bool> deleteMessage(int id) async {
    try {
      final r = await http.delete(Uri.parse('$_base/messages/$id'), headers: _headers());
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Réagit à un message. Retourne la liste à jour des réactions, ou null en cas d'échec.
  Future<List<dynamic>?> reactToMessage(int id, String emoji) async {
    try {
      final r = await http.post(
        Uri.parse('$_base/messages/$id/react'),
        headers: _headers(json: true),
        body: jsonEncode({'emoji': emoji}),
      );
      if (r.statusCode == 200) return jsonDecode(r.body) as List<dynamic>;
    } catch (_) {}
    return null;
  }

  Future<List<dynamic>> searchUsers(String term) async {
    try {
      final response = await http.get(
        Uri.parse('$_base/users/search?q=${Uri.encodeQueryComponent(term)}'),
        headers: _headers(),
      );
      if (response.statusCode == 200) return jsonDecode(response.body) as List<dynamic>;
    } catch (_) {}
    return [];
  }

  Future<Map<String, dynamic>?> startConversation(int otherUserId) async {
    try {
      final response = await http.post(
        Uri.parse('$_base/conversations'),
        headers: _headers(json: true),
        body: jsonEncode({'other_user_id': otherUserId}),
      );
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      }
    } catch (_) {}
    return null;
  }

  /// Une vidéo précise (ouverte depuis une notification). null si introuvable.
  Future<Map<String, dynamic>?> fetchVideo(int id) async {
    try {
      final response = await http.get(Uri.parse('$_base/videos/$id'), headers: _headers());
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      }
    } catch (_) {}
    return null;
  }

  /// Amis = personnes que je suis et qui me suivent aussi (les plus récemment contactés d'abord).
  Future<List<dynamic>> fetchFriends() async {
    try {
      final response = await http.get(Uri.parse('$_base/users/friends'), headers: _headers());
      if (response.statusCode == 200) return jsonDecode(response.body) as List<dynamic>;
    } catch (_) {}
    return [];
  }

  /// Envoie une vidéo à un ami dans la messagerie REEM
  /// (même format de message `REEM_VIDEO:` que le partage existant : la conversation l'affiche en carte).
  Future<bool> sendVideoToUser(int userId, app_models.Video video, String link) async {
    try {
      final conversation = await startConversation(userId);
      if (conversation == null) return false;

      final response = await http.post(
        Uri.parse('$_base/conversations/${conversation['id']}/messages'),
        headers: _headers(json: true),
        body: jsonEncode({
          'body': 'REEM_VIDEO:${jsonEncode({
            'id': video.id,
            'title': video.title,
            'description': video.description,
            'video_url': link,
            'username': video.username,
            'author_id': video.authorId,
            'likes_count': video.likesCount,
            'comments_count': video.commentsCount,
            'is_liked': false,
            'is_favorited': false,
          })}',
        }),
      );
      return response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// Signale une vidéo. Retourne null si c'est envoyé, sinon le message d'erreur à afficher.
  Future<String?> reportVideo(int videoId, String reason, {String? details}) async {
    try {
      final response = await http.post(
        Uri.parse('$_base/videos/$videoId/report'),
        headers: _headers(json: true),
        body: jsonEncode({'reason': reason, if (details != null) 'details': details}),
      );
      if (response.statusCode == 201 || response.statusCode == 200) return null;
      final body = jsonDecode(response.body);
      if (body is Map && body['message'] != null) return body['message'].toString();
      return 'Impossible d’envoyer le signalement.';
    } catch (_) {
      return 'Impossible d’envoyer le signalement.';
    }
  }
}
