import 'dart:convert';

import 'package:http/http.dart' as http;

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
}
