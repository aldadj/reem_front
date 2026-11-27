import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../services/app_settings.dart';
import '../services/auth_service.dart';
import '../services/session_manager.dart';
import '../theme/reem_theme.dart';
import '../widgets/publish_form.dart';

/// Publication depuis le navigateur : fichier choisi + formulaire (titre, description, visibilité).
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
  final TextEditingController _descriptionController = TextEditingController();
  final SessionManager _sessionManager = SessionManager();

  String _visibility = AppSettings.instance.defaultVisibility;
  bool _isSending = false;

  final int _maxVideoBytes = 100 * 1024 * 1024;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  String _getMimeType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
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
    if (_isSending) return;

    final description = _descriptionController.text.trim();
    if (widget.videoBytes.isEmpty) {
      _showMessage('La vidéo est vide ou invalide.');
      return;
    }
    if (widget.videoBytes.length > _maxVideoBytes) {
      _showMessage('La vidéo dépasse la taille maximale de 100 Mo.');
      return;
    }

    final token = _sessionManager.authToken;
    if (token == null || token.isEmpty) {
      _showMessage('Tu dois être connecté pour publier une vidéo.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSending = true);

    try {
      final request = http.MultipartRequest('POST', Uri.parse('${AuthService.baseUrl}/videos'));
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';

      if (description.isNotEmpty) {
        request.fields['title'] = titleFromCaption(description);
        request.fields['description'] = description;
      }
      request.fields['visibility'] = _visibility;

      request.files.add(
        http.MultipartFile.fromBytes(
          'video',
          widget.videoBytes,
          filename: widget.fileName,
          contentType: MediaType.parse(_getMimeType(widget.fileName)),
        ),
      );

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (!mounted) return;
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vidéo publiée avec succès !')),
        );
        Navigator.pop(context, true);
        return;
      }

      if (!mounted) return;
      setState(() => _isSending = false);
      _showMessage(parsePublishError(response.body));
    } catch (e) {
      debugPrint('Erreur publication web : $e');
      if (!mounted) return;
      setState(() => _isSending = false);
      _showMessage('Erreur lors de la publication. Vérifie ta connexion.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Écran toujours sombre, comme le reste de la création de vidéo
    return Theme(
      data: ReemTheme.dark(),
      child: Builder(builder: _buildBody),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06030F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Nouvelle publication',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: _isSending ? null : () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: ReemColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: ReemColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: ReemColors.gradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.movie_rounded, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _formatBytes(widget.videoBytes.length),
                                style: const TextStyle(color: ReemColors.textMuted, fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  PublishForm(
                    captionController: _descriptionController,
                    visibility: _visibility,
                    enabled: !_isSending,
                    onVisibilityChanged: (value) => setState(() => _visibility = value),
                  ),
                  const SizedBox(height: 22),
                  if (_isSending) ...[
                    const ClipRRect(
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                      child: LinearProgressIndicator(minHeight: 5),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Publication en cours… ne ferme pas cette page.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: ReemColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                  ],
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isSending ? null : _publishVideo,
                      icon: const Icon(Icons.publish_rounded),
                      label: Text(_isSending ? 'Publication…' : 'Publier'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
