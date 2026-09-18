import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  static const String baseUrl = 'https://reem-api-igdv.onrender.com/api';

  Future<Map<String, dynamic>?> login(
    String email,
    String password,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      final error = jsonDecode(response.body);
      throw error['message'] ?? 'Erreur de connexion';
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> register(
    String name,
    String email,
    String password, {
    String? imagePath,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/register'),
      );

      request.headers.addAll({
        'Accept': 'application/json',
      });

      request.fields['name'] = name;
      request.fields['email'] = email;
      request.fields['password'] = password;

      if (imagePath != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'profile_photo',
            imagePath,
          ),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(
        streamedResponse,
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      final error = jsonDecode(response.body);
      throw error['message'] ?? 'Erreur lors de l\'inscription';
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getUser(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      return null;
    } catch (e) {
      throw Exception(
        'Erreur lors de la récupération de l\'utilisateur: $e',
      );
    }
  }

  Future<Map<String, dynamic>?> updateProfilePhoto(
    String token,
    String imagePath,
  ) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/user/update-photo'),
      );

      request.headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      });

      request.files.add(
        await http.MultipartFile.fromPath(
          'profile_photo',
          imagePath,
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(
        streamedResponse,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      final error = jsonDecode(response.body);
      throw error['message'] ?? 'Erreur lors de la mise à jour';
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> updateProfileInfo(
    String token,
    String name,
  ) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/user/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'name': name,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      final error = jsonDecode(response.body);
      throw error['message'] ??
          'Erreur lors de la mise à jour du profil';
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> deleteProfilePhoto(
    String token,
  ) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/user/photo'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      final error = jsonDecode(response.body);
      throw error['message'] ??
          'Erreur lors de la suppression';
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> loginWithGoogle(
    String googleToken,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/google-login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'token': googleToken,
        }),
      );

      if (response.statusCode == 200 ||
          response.statusCode == 201) {
        return jsonDecode(response.body);
      }

      final error = jsonDecode(response.body);
      throw error['message'] ??
          'Erreur de connexion Google';
    } catch (e) {
      rethrow;
    }
  }
}
