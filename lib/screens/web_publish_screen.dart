import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../services/auth_service.dart';
import '../services/session_manager.dart';

class WebPublishScreen extends StatefulWidget {
  final Uint8List videoBytes;
  final String fileName;

  const WebPublishScreen({
    super.key,
    required this.videoBytes,
    required this.fileName,
  });

  @override
  State<WebPublishScreen> createState() => _WebPublishScreenState();
}

class _WebPublishScreenState extends State<WebPublishScreen> {
  final TextEditingController _titleController =
      TextEditingController();

  final SessionManager _sessionManager =
      SessionManager();

  bool _isSending = false;
  double _uploadProgress = 0;

  final int _maxVideoBytes = 100 * 1024 * 1024;

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  String _getMimeType(String fileName) {
    final extension =
        fileName.split('.').last.toLowerCase();

    switch (extension) {
      case 'mp4':
        return 'video/mp4';

      case 'mov':
        return 'video/quicktime';

      case 'avi':
        return 'video/x-msvideo';

      case 'mkv':
        return 'video/x-matroska';

      case 'webm':
        return 'video/webm';

      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _publishVideo() async {
    final title =
        _titleController.text.trim();

    if (title.isEmpty) {
      _showMessage(
        'Veuillez ajouter une légende.',
      );
      return;
    }

    if (widget.videoBytes.isEmpty) {
      _showMessage(
        'La vidéo est vide ou invalide.',
      );
      return;
    }

    if (widget.videoBytes.length >
        _maxVideoBytes) {
      _showMessage(
        'La vidéo dépasse la taille maximale de 100 Mo.',
      );
      return;
    }

    final token =
        _sessionManager.authToken;

    if (token == null || token.isEmpty) {
      _showMessage(
        'Vous devez être connecté pour publier une vidéo.',
      );
      return;
    }

    setState(() {
      _isSending = true;
      _uploadProgress = 0;
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(
          '${AuthService.baseUrl}/videos',
        ),
      );

      request.headers['Authorization'] =
          'Bearer $token';

      request.headers['Accept'] =
          'application/json';

      request.fields['title'] = title;
      request.fields['description'] = title;
      request.fields['caption'] = title;
      request.fields['visibility'] = 'public';

      final mimeType =
          _getMimeType(widget.fileName);

      request.files.add(
        http.MultipartFile.fromBytes(
          'video',
          widget.videoBytes,
          filename: widget.fileName,
          contentType: MediaType.parse(
            mimeType,
          ),
        ),
      );

      debugPrint(
        '🚀 Publication Web de la vidéo...',
      );

      debugPrint(
        '🌐 API: ${AuthService.baseUrl}/videos',
      );

      debugPrint(
        '📦 Fichier: ${widget.fileName}',
      );

      debugPrint(
        '📦 Taille: ${_formatBytes(widget.videoBytes.length)}',
      );

      final response =
          await request.send();

      final responseBody =
          await response.stream.bytesToString();

      debugPrint(
        '📡 Status: ${response.statusCode}',
      );

      debugPrint(
        '📡 Réponse: $responseBody',
      );

      if (response.statusCode == 200 ||
          response.statusCode == 201) {
        if (!mounted) return;

        setState(() {
          _uploadProgress = 1;
          _isSending = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Reel publié avec succès ! 🔥',
            ),
          ),
        );

        Navigator.pop(context, true);
        return;
      }

      String message =
          'Échec de la publication.';

      if (responseBody.isNotEmpty) {
        message = responseBody;
      }

      if (mounted) {
        setState(() {
          _isSending = false;
        });

        _showMessage(message);
      }
    } catch (e) {
      debugPrint(
        '❌ Erreur publication Web: $e',
      );

      if (!mounted) return;

      setState(() {
        _isSending = false;
      });

      _showMessage(
        'Erreur lors de la publication : $e',
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size =
        _formatBytes(widget.videoBytes.length);

    return Scaffold(
      backgroundColor:
          const Color(0xFF060816),
      appBar: AppBar(
        backgroundColor:
            Colors.transparent,
        elevation: 0,
        title: const Text(
          'Publier',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
          ),
          onPressed: _isSending
              ? null
              : () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(
            maxWidth: 600,
          ),
          child: Padding(
            padding:
                const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color:
                        const Color(0xFF10172A),
                    borderRadius:
                        BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.video_file,
                        color:
                            Colors.deepPurpleAccent,
                        size: 70,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        widget.fileName,
                        textAlign:
                            TextAlign.center,
                        style:
                            const TextStyle(
                          color: Colors.white,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        size,
                        style:
                            const TextStyle(
                          color:
                              Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                TextField(
                  controller:
                      _titleController,
                  enabled: !_isSending,
                  style:
                      const TextStyle(
                    color: Colors.white,
                  ),
                  decoration:
                      InputDecoration(
                    hintText:
                        'Ajoutez une légende...',
                    hintStyle:
                        const TextStyle(
                      color: Colors.white38,
                    ),
                    filled: true,
                    fillColor:
                        const Color(0xFF1A1A2E),
                    border:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(
                        12,
                      ),
                      borderSide:
                          BorderSide.none,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                if (_isSending) ...[
                  LinearProgressIndicator(
                    value: _uploadProgress > 0
                        ? _uploadProgress
                        : null,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Publication en cours...',
                    style: TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed:
                        _isSending
                            ? null
                            : _publishVideo,
                    style:
                        ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(
                        0xFF7C4DFF,
                      ),
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(
                          12,
                        ),
                      ),
                    ),
                    child: Text(
                      _isSending
                          ? 'Publication...'
                          : 'Publier',
                      style:
                          const TextStyle(
                        color: Colors.white,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}