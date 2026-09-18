```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/video.dart';

class ApiService {
  static const String baseUrl = 'https://reem-api-igdv.onrender.com/api';

  Future<List<Video>> fetchVideos() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/videos'),
        headers: {
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final dynamic decodedData = jsonDecode(response.body);

        if (decodedData is List) {
          return decodedData
              .map((dynamic item) => Video.fromJson(item))
              .toList();
        }

        if (decodedData is Map<String, dynamic>) {
          final dynamic videoData =
              decodedData['videos'] ?? decodedData['data'];

          if (videoData is List) {
            return videoData
                .map((dynamic item) => Video.fromJson(item))
                .toList();
          }
        }

        throw Exception(
          'Format JSON reçu non reconnu par l\'application',
        );
      }

      throw Exception(
        'Erreur serveur : ${response.statusCode}',
      );
    } catch (e) {
      throw Exception(
        'Impossible de se connecter au serveur REEM : $e',
      );
    }
  }
}
```
