import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../services/auth_service.dart';
import '../services/session_manager.dart';
import 'video_trim_screen.dart';
import 'package:video_trimmer/video_trimmer.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';

class PublishScreen extends StatefulWidget {
  final String videoPath;

  const PublishScreen({super.key, required this.videoPath});

  @override
  State<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<PublishScreen> {
  final TextEditingController _titleController = TextEditingController();
  final Trimmer _trimmer = Trimmer();
  double _startValue = 0.0;
  double _endValue = 0.0;
  bool _isTrimmerLoading = true;
  bool _isSaving = false;
  bool _isPlaying = false;
  int _selectedFilterIndex = 0; // 0 pour "Aucun"
  bool _isSending = false;
  double _uploadProgress = 0;
  String? _videoFileName;
  int? _videoFileSize;
  String? _fileErrorMessage;
  final int _maxVideoBytes = 100 * 1024 * 1024;
  late String _currentVideoPath;
  http.Client? _client;
  final SessionManager _sessionManager = SessionManager();

  // Liste des filtres disponibles
  final List<Map<String, dynamic>> _filters = [
    {'name': 'Aucun', 'filter': const ColorFilter.mode(Colors.transparent, BlendMode.dst)},
    {'name': 'Vintage', 'filter': const ColorFilter.matrix([0.393, 0.769, 0.189, 0, 0, 0.349, 0.686, 0.168, 0, 0, 0.272, 0.534, 0.131, 0, 0, 0, 0, 0, 1, 0])},
    {'name': 'Gris', 'filter': const ColorFilter.matrix([0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0, 0, 0, 1, 0])},
    {'name': 'Sépia', 'filter': const ColorFilter.matrix([0.393, 0.769, 0.189, 0, 0, 0.349, 0.686, 0.168, 0, 0, 0.272, 0.534, 0.131, 0, 0, 0, 0, 0, 1, 0])},
    {'name': 'Froid', 'filter': const ColorFilter.mode(Colors.blue, BlendMode.overlay)},
    {'name': 'Chaud', 'filter': const ColorFilter.mode(Colors.orange, BlendMode.overlay)},
  ];

  // Commande FFmpeg pour le filtre Sépia (exemple)
  final String _ffmpegSepiaFilter = "-vf colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131";
  final String _ffmpegGrayscaleFilter = "-vf format=gray";

  @override
  void initState() {
    super.initState();
    _currentVideoPath = widget.videoPath;
    _loadVideoForTrimming();
  }

  Future<void> _loadVideoForTrimming() async {
    setState(() => _isTrimmerLoading = true);
    await _trimmer.loadVideo(videoFile: File(_currentVideoPath));
    // Règle le volume à 100% car il est souvent à 0 par défaut
    await _trimmer.videoPlayerController?.setVolume(1.0);
    final duration = _trimmer.videoPlayerController?.value.duration;
    if (duration != null) {
      _endValue = duration.inMilliseconds.toDouble();
    }
    if (mounted) {
      setState(() {
        _isTrimmerLoading = false;
        _prepareVideoInfo();
      });
    }
  }

  void _prepareVideoInfo() {
    final videoFile = File(_currentVideoPath);
    _videoFileName = _getFileName(_currentVideoPath);

    if (!videoFile.existsSync()) {
      _fileErrorMessage = 'Fichier vidéo introuvable.';
      _videoFileSize = null;
      return;
    }

    _videoFileSize = videoFile.lengthSync();
    if (_videoFileSize != null && _videoFileSize! > _maxVideoBytes) {
      _fileErrorMessage = 'La vidéo dépasse la taille maximale de 100 Mo.';
    } else {
      _fileErrorMessage = null;
    }
  }

  // Fonction qui envoie le fichier vidéo et les textes à ton API Laravel
  Future<void> _uploadVideoToLaravel() async {
    setState(() => _isSaving = true);

    // 1. On sauvegarde d'abord la vidéo découpée
    await _trimmer.saveTrimmedVideo(
      startValue: _startValue,
      endValue: _endValue,
      onSave: (outputPath) {
        if (!mounted || outputPath == null) {
          setState(() => _isSaving = false);
          return;
        }

        // Si un filtre est sélectionné (autre que "Aucun")
        if (_selectedFilterIndex > 0) {
          _applyFilterWithFFmpeg(outputPath).then((filteredPath) {
            setState(() => _isSaving = false);
            if (filteredPath != null) {
              _performUpload(filteredPath);
            } else {
              _showErrorSnackBar("Impossible d'appliquer le filtre à la vidéo.");
            }
          });
        } else {
          // Pas de filtre, on upload directement la vidéo découpée
          setState(() => _isSaving = false);
          _performUpload(outputPath);
        }
      },
    );
  }

  Future<String?> _applyFilterWithFFmpeg(String inputPath) async {
    final String outputPath = '${inputPath.substring(0, inputPath.lastIndexOf('.'))}_filtered.mp4';
    String filterCommand = "";

    if (_filters[_selectedFilterIndex]['name'] == 'Sépia' || _filters[_selectedFilterIndex]['name'] == 'Vintage') {
      filterCommand = _ffmpegSepiaFilter;
    } else if (_filters[_selectedFilterIndex]['name'] == 'Gris') {
      filterCommand = _ffmpegGrayscaleFilter;
    } else {
      // Pour les filtres de couleur simple, FFmpeg est plus complexe.
      // Pour cet exemple, nous ne traitons que Sépia et Gris.
      debugPrint("Ce filtre n'est pas encore supporté par FFmpeg dans cet exemple.");
      return inputPath; // On retourne le chemin original si le filtre n'est pas géré
    }

    final command = "-i $inputPath $filterCommand -y $outputPath";
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (returnCode!.isValueSuccess()) {
      return outputPath;
    } else {
      debugPrint("Erreur FFmpeg : ${await session.getLogsAsString()}");
      return null;
    }
  }

  Future<void> _performUpload(String videoPath) async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Veuillez donner un titre à votre Reel !")),
      );
      return;
    }
    setState(() {
      _isSending = true;
      _uploadProgress = 0;
    });

    // L'URL de ton API Laravel (identique à ton flux)
    final String apiUrl = "${AuthService.baseUrl}/videos";
    final String? token = _sessionManager.authToken;
    if (token == null || token.isEmpty) {
      if (mounted) {
        _showErrorSnackBar('Vous devez être connecté pour publier une vidéo.');
      }
      setState(() => _isSending = false);
      return;
    }

    _client = http.Client();

    try {
      // Utilisation de ProgressMultipartRequest pour suivre l'avancement
      var request = ProgressMultipartRequest(
        'POST',
        Uri.parse(apiUrl),
        onProgress: (bytes, total) {
          if (mounted) {
            setState(() {
              _uploadProgress = total > 0 ? bytes / total : 0;
            });
          }
        },
      );

      // Ajout du token d'authentification si l'utilisateur est connecté
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';

      // 1. Ajout des champs textes
      request.fields['title'] = _titleController.text.trim();
      request.fields['description'] = _titleController.text.trim(); // La description est maintenant le titre
      request.fields['caption'] = _titleController.text.trim();
      request.fields['visibility'] = 'public';

      // 2. Vérification du fichier vidéo et ajout du bon type MIME
      final videoFile = File(videoPath);
      if (!videoFile.existsSync()) {
        throw Exception('Fichier vidéo introuvable : $videoPath');
      }
      _videoFileName = _getFileName(videoPath);
      _videoFileSize = videoFile.lengthSync();
      if (_videoFileSize != null && _videoFileSize! > _maxVideoBytes) {
        throw Exception('La vidéo dépasse la taille maximale de 100 Mo.');
      }
      if (_fileErrorMessage != null) {
        throw Exception(_fileErrorMessage!);
      }
      final mimeType = _getVideoMimeType(videoPath);
      request.files.add(await http.MultipartFile.fromPath(
        'video',
        videoPath,
        contentType: MediaType.parse(mimeType),
      ));

      debugPrint("🚀 Envoi de la vidéo en cours vers Laravel...");
      final streamedResponse = await _client!.send(request);
      final response = await http.Response.fromStream(streamedResponse);
      debugPrint('🔧 PublishResponse status=${response.statusCode} body=${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint("✅ Vidéo publiée avec succès !");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Reel publié avec succès ! 🔥")),
          );
          // On retourne 'true' pour dire au FeedScreen de rafraîchir la liste
          Navigator.pop(context, true);
        }
      } else {
        debugPrint("❌ Erreur Laravel, code statut : ${response.statusCode}");
        String message = 'Échec de la publication.';
        try {
          final body = jsonDecode(response.body);
          if (body is Map && body['message'] is String) {
            message = body['message'];
          } else if (body is Map) {
            message = body.toString();
          }
        } catch (_) {}
        if (mounted) _showErrorSnackBar(message);
      }
    } catch (e) {
      // Si l'erreur est due à la fermeture du client (annulation)
      if (e is http.ClientException || e.toString().contains('Connection closed')) {
        debugPrint("ℹ️ Téléversement annulé par l'utilisateur.");
      } else {
        debugPrint("❌ Erreur réseau lors de la publication : $e");
        if (mounted) _showErrorSnackBar('Erreur réseau lors de la publication : $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _client = null;
        });
      }
    }
  }

  void _cancelUpload() {
    if (_client != null) {
      _client!.close();
      _client = null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Téléversement annulé.")),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _getFileName(String filePath) {
    final parts = filePath.split(RegExp(r'[\\/]+'));
    return parts.isNotEmpty ? parts.last : filePath;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  String _getVideoMimeType(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    switch (extension) {
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'mkv':
        return 'video/x-matroska';
      default:
        return 'application/octet-stream';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _trimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060816),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Publier", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isSending
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 102,
                        height: 102,
                        child: CircularProgressIndicator(
                          value: _uploadProgress,
                          strokeWidth: 8,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                        ),
                      ),
                      Text(
                        "${(_uploadProgress * 100).toInt()}%",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Téléversement en cours…",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withAlpha(204), fontSize: 15),
                  ),
                  const SizedBox(height: 30),
                  TextButton(
                    onPressed: _cancelUpload,
                    child: const Text(
                      "Annuler",
                      style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ) : _buildEditor(),
    );
  }

  Widget _buildEditor() {
    return Column(
      children: [
        Expanded(
          child: _isTrimmerLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
              : Stack(
                  children: [
                    ColorFiltered(
                      colorFilter: _filters[_selectedFilterIndex]['filter'],
                      child: VideoViewer(trimmer: _trimmer),
                    ),
                    // Le bouton play/pause est mis au centre
                    Center(
                      child: IconButton(
                      icon: Icon(
                        _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        color: Colors.white.withOpacity(0.8),
                        size: 60,
                      ),
                      onPressed: () async {
                        final playbackState = await _trimmer.videoPlaybackControl(
                          startValue: _startValue,
                          endValue: _endValue,
                        );
                        setState(() => _isPlaying = playbackState);
                      },
                    ),
                    ),
                  ],
                ),
        ),
        Container(
          color: const Color(0xFF0F1628),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Liste des filtres
              SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _filters.length,
                  itemBuilder: (context, index) {
                    final filter = _filters[index];
                    return GestureDetector(
                      onTap: () => setState(() => _selectedFilterIndex = index),
                      child: Container(
                        width: 60,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(8),
                          border: _selectedFilterIndex == index
                              ? Border.all(color: Colors.redAccent, width: 2)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          filter['name'],
                          style: const TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Trimmer
              if (!_isTrimmerLoading)
                TrimViewer(
                  trimmer: _trimmer,
                  viewerHeight: 50.0,
                  viewerWidth: MediaQuery.of(context).size.width,
                  durationStyle: DurationStyle.FORMAT_MM_SS,
                  onChangeStart: (value) => _startValue = value,
                  onChangeEnd: (value) => _endValue = value,
                  onChangePlaybackState: (value) => setState(() => _isPlaying = value),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ajoutez une légende...',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: const Color(0xFF1A1A2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C4DFF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    disabledBackgroundColor: Colors.grey.shade800,
                  ),
                  onPressed: (_isSending || _isSaving || _fileErrorMessage != null) ? null : _uploadVideoToLaravel,
                  child: _isSaving
                      ? const Text('Préparation...', style: TextStyle(color: Colors.white))
                      : const Text(
                          'Publier',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: subtitle.startsWith('Un extrait') ? Colors.greenAccent.withOpacity(0.8) : Colors.white54,
          fontSize: 12,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
      enabled: onTap != null,
    );
  }
}

// Classe utilitaire pour intercepter le flux de données et calculer la progression
class ProgressMultipartRequest extends http.MultipartRequest {
  final Function(int bytes, int totalBytes) onProgress;

  ProgressMultipartRequest(super.method, super.url, {required this.onProgress});

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    final total = contentLength;
    int bytesSent = 0;

    final transformer = StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (List<int> data, EventSink<List<int>> sink) {
        bytesSent += data.length;
        onProgress(bytesSent, total);
        sink.add(data);
      },
    );

    return http.ByteStream(byteStream.transform(transformer));
  }
}