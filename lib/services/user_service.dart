import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class UserService {
  Future<Map<String, dynamic>?> fetchProfile(int userId, {String? token}) async {
    final response = await http.get(
      Uri.parse('${AuthService.baseUrl}/users/$userId'),
      headers: token != null
          ? {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            }
          : {'Accept': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  }

  Future<List<dynamic>> fetchUserVideos(int userId, {String? token}) async {
    final response = await http.get(
      Uri.parse('${AuthService.baseUrl}/users/$userId/videos'),
      headers: token != null
          ? {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            }
          : {'Accept': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    return [];
  }

  Future<List<dynamic>> fetchLikedVideos({String? token}) async {
    final response = await http.get(
      Uri.parse('${AuthService.baseUrl}/user/liked-videos'),
      headers: token != null
          ? {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            }
          : {'Accept': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    return [];
  }

  Future<Map<String, dynamic>?> toggleFollow(int userId, String token) async {
    final response = await http.post(
      Uri.parse('${AuthService.baseUrl}/users/$userId/follow'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    return null;
  }

  Future<bool> deleteVideo(int videoId, String token) async {
    final response = await http.delete(
      Uri.parse('${AuthService.baseUrl}/videos/$videoId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      },
    );

    return response.statusCode == 200;
  }

  /// Épingle / désépingle une vidéo de son propre profil.
  /// Retourne {ok, pinned, pinned_at, message}.
  Future<Map<String, dynamic>> togglePin(int videoId, String token) async {
    try {
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/videos/$videoId/pin'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      Map<String, dynamic> body = {};
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}
      if (response.statusCode == 200) {
        return {...body, 'ok': true};
      }
      return {
        'ok': false,
        'message': body['message'] ?? 'Impossible d’épingler cette vidéo.',
      };
    } catch (_) {
      return {'ok': false, 'message': 'Erreur réseau'};
    }
  }
}
