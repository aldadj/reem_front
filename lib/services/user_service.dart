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
}
