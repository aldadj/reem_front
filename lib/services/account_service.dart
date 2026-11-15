import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'session_manager.dart';

/// Tout ce qui touche au compte : infos du profil, photo, mot de passe, suppression.
/// Les erreurs sont lancées sous forme de texte lisible (`throw 'message'`).
class AccountService {
  final SessionManager _session = SessionManager();

  Map<String, String> _headers({bool json = false}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_session.authToken}',
      };

  Map<String, dynamic> _parse(http.Response response, String fallbackError) {
    Map<String, dynamic> body = {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}

    if (response.statusCode >= 200 && response.statusCode < 300) return body;

    // Erreurs de validation Laravel : on affiche la première
    final errors = body['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) throw first.first.toString();
    }
    throw (body['message']?.toString() ?? fallbackError);
  }

  /// Met à jour la session avec l'utilisateur renvoyé par le serveur.
  Map<String, dynamic> _remember(Map<String, dynamic> body) {
    final user = body['user'];
    if (user is Map) {
      final merged = Map<String, dynamic>.from(_session.currentUser ?? {})
        ..addAll(Map<String, dynamic>.from(user));
      _session.setUser(merged);
      return merged;
    }
    return _session.currentUser ?? {};
  }

  Future<Map<String, dynamic>> updateInfo({
    required String name,
    required String username,
    required String bio,
    required String website,
  }) async {
    final response = await http.put(
      Uri.parse('${AuthService.baseUrl}/user/info'),
      headers: _headers(json: true),
      body: jsonEncode({
        'name': name,
        'username': username,
        'bio': bio,
        'website': website,
      }),
    );
    return _remember(_parse(response, 'Impossible de modifier le profil.'));
  }

  Future<Map<String, dynamic>> uploadPhoto(Uint8List bytes, String filename) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${AuthService.baseUrl}/user/profile-photo'),
    )
      ..headers.addAll(_headers())
      ..files.add(http.MultipartFile.fromBytes('profile_photo', bytes, filename: filename));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return _remember(_parse(response, 'Impossible d’envoyer la photo.'));
  }

  Future<Map<String, dynamic>> deletePhoto() async {
    final response = await http.delete(
      Uri.parse('${AuthService.baseUrl}/user/photo'),
      headers: _headers(),
    );
    return _remember(_parse(response, 'Impossible de supprimer la photo.'));
  }

  Future<void> changePassword({
    String? currentPassword,
    required String newPassword,
    required String confirmation,
  }) async {
    final response = await http.put(
      Uri.parse('${AuthService.baseUrl}/user/password'),
      headers: _headers(json: true),
      body: jsonEncode({
        if (currentPassword != null && currentPassword.isNotEmpty) 'current_password': currentPassword,
        'password': newPassword,
        'password_confirmation': confirmation,
      }),
    );
    _parse(response, 'Impossible de changer le mot de passe.');
  }

  Future<void> deleteAccount({String? password, required String confirmation}) async {
    final response = await http.delete(
      Uri.parse('${AuthService.baseUrl}/user'),
      headers: _headers(json: true),
      body: jsonEncode({
        if (password != null && password.isNotEmpty) 'password': password,
        'confirmation': confirmation,
      }),
    );
    _parse(response, 'Impossible de supprimer le compte.');
  }
}
