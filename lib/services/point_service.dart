import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:reem_front/services/session_manager.dart';
import 'package:reem_front/services/auth_service.dart';

class PointService {
  /// Récupère le solde et le niveau de l'utilisateur connecté
  static Future<Map<String, dynamic>?> getBalance() async {
    try {
      final token = SessionManager().authToken;
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/user/points/balance'),
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
      print('Erreur PointService: $e');
      return null;
    }
  }
}