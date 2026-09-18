import 'dart:convert';
import 'dart:io'; // Nécessaire pour détecter la plateforme (Platform.isAndroid)
import 'package:http/http.dart' as http;
import '../models/video.dart';

class ApiService {
  // Détection dynamique de l'adresse de l'API Laravel
  static String get baseUrl {
    if (Platform.isAndroid) {
      return "http://10.0.2.2:8000/api"; // Pour l'émulateur Android
    } else {
      return "http://127.0.0.1:8000/api"; // Pour l'application native Windows / Web / Mac
    }
  }

  Future<List<Video>> fetchVideos() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/videos'));

      if (response.statusCode == 200) {
        final dynamic decodedData = jsonDecode(response.body);
        
        // Cas 1 : Laravel renvoie directement une liste [...]
        if (decodedData is List) {
          return decodedData.map((dynamic item) => Video.fromJson(item)).toList();
        } 
        
        // Cas 2 : Laravel renvoie un objet {...} qui contient une clé 'videos' ou 'data'
        else if (decodedData is Map<String, dynamic>) {
          final List<dynamic>? videoList = decodedData['videos'] ?? decodedData['data'];
          if (videoList != null) {
            return videoList.map((dynamic item) => Video.fromJson(item)).toList();
          }
        }
        
        throw Exception("Format JSON reçu non reconnu par l'application");
      } else {
        throw Exception("Erreur serveur : ${response.statusCode}");
      }
    } catch (e) {
      throw Exception("Impossible de se connecter au serveur Laravel : $e");
    }
  }
}