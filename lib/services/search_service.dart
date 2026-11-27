import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'session_manager.dart';

/// Résultats d'une recherche : personnes, vidéos et hashtags.
class SearchResults {
  const SearchResults({
    this.users = const [],
    this.videos = const [],
    this.hashtags = const [],
  });

  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> videos;
  final List<Map<String, dynamic>> hashtags;

  bool get isEmpty => users.isEmpty && videos.isEmpty && hashtags.isEmpty;
}

class SearchService {
  final SessionManager _session = SessionManager();

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (_session.isAuthenticated) 'Authorization': 'Bearer ${_session.authToken}',
      };

  List<Map<String, dynamic>> _maps(dynamic raw) {
    if (raw is! List) return [];
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  /// [type] : top | users | videos | hashtags
  Future<SearchResults?> search(String query, String type) async {
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/search?type=$type&q=${Uri.encodeQueryComponent(query)}'),
        headers: _headers,
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return SearchResults(
        users: _maps(data['users']),
        videos: _maps(data['videos']),
        hashtags: _maps(data['hashtags']),
      );
    } catch (_) {
      return null;
    }
  }

  /// Hashtags du moment (calculés par le serveur sur les vidéos récentes).
  Future<List<Map<String, dynamic>>> trendingHashtags() async {
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/search/suggestions'),
        headers: _headers,
      );
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return _maps(data['hashtags']);
    } catch (_) {
      return [];
    }
  }
}
