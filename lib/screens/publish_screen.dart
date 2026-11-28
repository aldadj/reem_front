import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/app_settings.dart';
import '../theme/reem_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/auth_service.dart';
import '../services/session_manager.dart';
import '../services/story_service.dart';
import '../utils/media_url.dart';
import '../services/video_edit_service.dart';
import '../widgets/publish_form.dart';

class PublishScreen extends StatefulWidget {
  final String videoPath;

  const PublishScreen({
    super.key,
    required this.videoPath,
  });

  @override
  State<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<PublishScreen> {
  final TextEditingController _descriptionController = TextEditingController();
  String _visibility = AppSettings.instance.defaultVisibility;

  final VideoEditService _videoEditService = VideoEditService();
  late final Player _player;
  late final VideoController _playerController;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;

  double _startValue = 0.0;
  double _endValue = 0.0;
  Duration _videoDuration = Duration.zero;
  Duration _videoPosition = Duration.zero;

  bool _isTrimmerLoading = true;
  bool _isSaving = false;
  bool _isPlaying = false;
  bool _isSending = false;
  bool _isMuted = false;
  bool _isFinalPreview = false;

  int _selectedFilterIndex = 0;

  // Recadrage : false = vidéo entière, true = remplit l'écran 9:16
  bool _cropFill = false;
  double _cropZoom = 1.0;
  double _cropPanX = 0.0;
  double _cropPanY = 0.0;
  double _gestureStartZoom = 1.0;

  double _uploadProgress = 0;

  String? _videoFileName;
  int? _videoFileSize;
  String? _fileErrorMessage;
  String? _musicPath;
  String? _preparedVideoPath;
  bool _isRestartingTrim = false;

  final int _maxVideoBytes = 100 * 1024 * 1024;

  late String _currentVideoPath;

  http.Client? _client;

  final SessionManager _sessionManager = SessionManager();

  /// Filtres disponibles.
  ///
  /// IMPORTANT :
  /// Ces filtres sont actuellement appliqués uniquement à l'aperçu.
  /// Ils ne sont pas intégrés au fichier vidéo final.
  final List<Map<String, dynamic>> _filters = [
    {
      'name': 'Aucun',
      'filter': const ColorFilter.mode(
        Colors.transparent,
        BlendMode.dst,
      ),
    },
    {
      'name': 'Vintage',
      'filter': const ColorFilter.matrix([
        0.393,
        0.769,
        0.189,
        0,
        0,
        0.349,
        0.686,
        0.168,
        0,
        0,
        0.272,
        0.534,
        0.131,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]),
    },
    {
      'name': 'Gris',
      'filter': const ColorFilter.matrix([
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]),
    },
    {
      'name': 'Sépia',
      'filter': const ColorFilter.matrix([
        0.393,
        0.769,
        0.189,
        0,
        0,
        0.349,
        0.686,
        0.168,
        0,
        0,
        0.272,
        0.534,
        0.131,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]),
    },
    {
      'name': 'Froid',
      'filter': const ColorFilter.mode(
        Colors.blue,
        BlendMode.overlay,
      ),
    },
    {
      'name': 'Chaud',
      'filter': const ColorFilter.mode(
        Colors.orange,
        BlendMode.overlay,
      ),
    },
  ];

  @override
  void initState() {
    super.initState();

    _currentVideoPath = widget.videoPath;
    _player = Player();
    _playerController = VideoController(_player);
    _positionSubscription = _player.stream.position.listen(_handlePositionChanged);
    _durationSubscription = _player.stream.duration.listen((duration) {
      if (duration > Duration.zero && mounted) {
        setState(() => _videoDuration = duration);
      }
    });
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });

    _loadVideoForTrimming();
  }

  Future<void> _loadVideoForTrimming() async {
    if (!mounted) return;

    setState(() {
      _isTrimmerLoading = true;
    });

    try {
      final videoFile = File(_currentVideoPath);

      if (!videoFile.existsSync()) {
        if (!mounted) return;

        setState(() {
          _isTrimmerLoading = false;
          _fileErrorMessage = 'Fichier vidéo introuvable.';
        });

        return;
      }

      _prepareVideoInfo();

      final duration = await _videoEditService.getDuration(_currentVideoPath);
      await _player.open(Media(Uri.file(_currentVideoPath).toString()), play: false);
      await _player.setPlaylistMode(PlaylistMode.single);
      await _player.setVolume(100);

      if (!mounted) return;

      _videoDuration = duration;
      _endValue = duration.inMilliseconds.toDouble();

      if (!mounted) return;

      setState(() {
        _isTrimmerLoading = false;
      });

      // La vidéo importée / filmée démarre tout de suite pour l'éditer.
      await _player.play();
    } catch (e) {
      debugPrint(
        '❌ Erreur lors du chargement de la vidéo : $e',
      );

      if (!mounted) return;

      setState(() {
        _isTrimmerLoading = false;
        _fileErrorMessage =
            'Impossible de charger la vidéo : $e';
      });
    }
  }

  Future<void> _pickMusic() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: true,
    );
    if (!mounted || result == null) return;

    final file = result.files.single;
    var path = file.path;
    if (path == null || !File(path).existsSync()) {
      final bytes = file.bytes;
      if (bytes != null && bytes.isNotEmpty) {
        final directory = await getTemporaryDirectory();
        path = '${directory.path}${Platform.pathSeparator}'
            'reem_music_${DateTime.now().microsecondsSinceEpoch}.${file.extension ?? 'audio'}';
        await File(path).writeAsBytes(bytes, flush: true);
      }
    }
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      _showErrorSnackBar('Impossible de lire ce fichier audio.');
      return;
    }

    setState(() {
      _musicPath = path;
      _preparedVideoPath = null;
      _isFinalPreview = false;
    });
  }

  Future<void> _prepareFinalPreview() async {
    if (_isSaving || _isSending) return;
    if (_fileErrorMessage != null) {
      _showErrorSnackBar(_fileErrorMessage!);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _player.pause();
      final outputPath = await _videoEditService.renderVideo(
        inputPath: _currentVideoPath,
        startMilliseconds: _startValue,
        endMilliseconds: _endValue,
        muteOriginal: _isMuted,
        filterName: _filters[_selectedFilterIndex]['name'] as String,
        musicPath: _musicPath,
        cropFill: _cropFill,
        zoom: _cropZoom,
        panX: _cropPanX,
        panY: _cropPanY,
      );
      await _player.open(Media(Uri.file(outputPath).toString()), play: false);
      await _player.setVolume(100);

      if (!mounted) return;

      setState(() {
        _preparedVideoPath = outputPath;
        _isFinalPreview = true;
        _videoPosition = Duration.zero;
        _isSaving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showErrorSnackBar('Impossible de préparer l’aperçu : $e');
    }
  }

  Future<void> _returnToEditor() async {
    await _player.pause();
    await _player.open(Media(Uri.file(_currentVideoPath).toString()), play: false);
    await _player.setVolume(100);
    if (!mounted) return;
    setState(() {
      _preparedVideoPath = null;
      _isFinalPreview = false;
      _videoPosition = Duration.zero;
    });
  }

  void _handlePositionChanged(Duration position) {
    if (!mounted) return;
    setState(() => _videoPosition = position);
    if (!_isFinalPreview &&
        _player.state.playing &&
        !_isRestartingTrim &&
        position.inMilliseconds >= _endValue &&
        _endValue > _startValue) {
      _isRestartingTrim = true;
      _player.pause().then((_) => _player.seek(Duration(milliseconds: _startValue.round()))).then((_) {
        if (mounted) return _player.play();
      }).whenComplete(() => _isRestartingTrim = false);
    }
  }

  Future<void> _toggleEditorPlayback() async {
    if (_player.state.playing) {
      await _player.pause();
      return;
    }
    if (_videoPosition.inMilliseconds < _startValue ||
        _videoPosition.inMilliseconds >= _endValue) {
      await _player.seek(Duration(milliseconds: _startValue.round()));
    }
    await _player.play();
  }

  String _formatDuration(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    final minutes = seconds ~/ 60;
    return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
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

    _fileErrorMessage = null;

    debugPrint(
      '🎥 Vidéo : $_videoFileName',
    );

    debugPrint(
      '📦 Taille : ${_videoFileSize != null ? _formatBytes(_videoFileSize!) : "inconnue"}',
    );
  }

  Future<void> _uploadVideoToLaravel() async {
    if (_isSaving || _isSending) return;

    if (_fileErrorMessage != null) {
      _showErrorSnackBar(
        _fileErrorMessage!,
      );
      return;
    }

    if (_preparedVideoPath == null) {
      _showErrorSnackBar('Prévisualisez la vidéo avant de la publier.');
      return;
    }

    await _performUpload(_preparedVideoPath!);
  }

  Future<void> _performUpload(String videoPath) async {
    FocusScope.of(context).unfocus();

    if (!mounted) return;

    setState(() {
      _isSending = true;
      _uploadProgress = 0;
    });

    final String apiUrl =
        '${AuthService.baseUrl}/videos';

    final String? token =
        _sessionManager.authToken;

    if (token == null || token.isEmpty) {
      if (mounted) {
        _showErrorSnackBar(
          'Vous devez être connecté pour publier une vidéo.',
        );

        setState(() {
          _isSending = false;
        });
      }

      return;
    }

    _client = http.Client();

    try {
      final videoFile = File(videoPath);

      if (!videoFile.existsSync()) {
        throw Exception(
          'Fichier vidéo introuvable : $videoPath',
        );
      }

      final videoSize = videoFile.lengthSync();

      if (videoSize > _maxVideoBytes) {
        throw Exception(
          'La vidéo dépasse la taille maximale de 100 Mo.',
        );
      }

      final mimeType =
          _getVideoMimeType(videoPath);

      final request = ProgressMultipartRequest(
        'POST',
        Uri.parse(apiUrl),
        onProgress: (bytes, total) {
          if (!mounted) return;

          setState(() {
            _uploadProgress =
                total > 0 ? bytes / total : 0;
          });
        },
      );

      request.headers['Authorization'] =
          'Bearer $token';

      request.headers['Accept'] =
          'application/json';

      // Une seule description, comme sur TikTok : le titre en est tiré automatiquement
      final description = _descriptionController.text.trim();
      if (description.isNotEmpty) {
        request.fields['title'] = titleFromCaption(description);
        request.fields['description'] = description;
      }

      request.fields['visibility'] = _visibility;

      _videoFileName =
          _getFileName(videoPath);

      _videoFileSize = videoSize;

      request.files.add(
        await http.MultipartFile.fromPath(
          'video',
          videoPath,
          contentType: MediaType.parse(
            mimeType,
          ),
        ),
      );

      debugPrint(
        '🚀 Envoi de la vidéo vers Laravel...',
      );

      debugPrint(
        '🌐 API : $apiUrl',
      );

      final streamedResponse =
          await _client!.send(request);

      final response =
          await http.Response.fromStream(
        streamedResponse,
      );

      debugPrint(
        '🔧 PublishResponse status=${response.statusCode}',
      );

      debugPrint(
        '🔧 PublishResponse body=${response.body}',
      );

      if (response.statusCode == 200 ||
          response.statusCode == 201) {
        debugPrint(
          '✅ Vidéo publiée avec succès !',
        );

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Reel publié avec succès ! 🔥',
            ),
          ),
        );

        // Retourne true au FeedScreen
        // pour demander un rafraîchissement.
        Navigator.pop(context, true);
      } else {
        debugPrint(
          '❌ Erreur Laravel : ${response.statusCode}',
        );

        final message =
            parsePublishError(response.body);

        if (mounted) {
          _showErrorSnackBar(message);
        }
      }
    } catch (e) {
      if (e is http.ClientException ||
          e.toString().contains(
            'Connection closed',
          )) {
        debugPrint(
          'ℹ️ Téléversement annulé.',
        );
      } else {
        debugPrint(
          '❌ Erreur réseau lors de la publication : $e',
        );

        if (mounted) {
          _showErrorSnackBar(
            'Erreur réseau lors de la publication : $e',
          );
        }
      }
    } finally {
      _client?.close();
      _client = null;

      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  void _cancelUpload() {
    if (_client != null) {
      _client!.close();
      _client = null;

      if (mounted) {
        setState(() {
          _isSending = false;
          _uploadProgress = 0;
        });

        _showErrorSnackBar(
          'Téléversement annulé.',
        );
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    });
  }

  String _getFileName(String filePath) {
    final parts =
        filePath.split(RegExp(r'[\\/]+'));

    return parts.isNotEmpty
        ? parts.last
        : filePath;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  String _getVideoMimeType(String filePath) {
    final extension =
        filePath.split('.').last.toLowerCase();

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
    _client?.close();

    _descriptionController.dispose();

    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playingSubscription?.cancel();
    _player.dispose();

    super.dispose();
  }

  // Écran toujours sombre (caméra, montage, photo) quel que soit le thème choisi
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ReemTheme.dark(),
      child: Builder(builder: _buildBody),
    );
  }

  Widget _buildBody(BuildContext context) {
    // Sur téléphone, l'écran d'édition est plein écran, façon TikTok (sans barre de titre)
    final mobileEditor = MediaQuery.sizeOf(context).width < 760 && !_isFinalPreview && !_isSending;

    return Scaffold(
      backgroundColor: const Color(0xFF06030F),
      appBar: mobileEditor ? null : AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _isFinalPreview ? 'Nouvelle publication' : 'Modifier la vidéo',
          style: const TextStyle(
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
          onPressed: () {
            if (_isSending) return;
            if (_isFinalPreview) {
              _returnToEditor();
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: _isSending
          ? _buildUploadProgress()
          : _isFinalPreview
            ? _buildFinalPreview()
            : _buildEditor(),
    );
  }

  Widget _buildUploadProgress() {
    return Center(
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
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
                  backgroundColor:
                      Colors.white24,
                  valueColor:
                      const AlwaysStoppedAnimation<
                          Color>(
                    ReemColors.primary,
                  ),
                ),
              ),
              Text(
                '${(_uploadProgress * 100).toInt()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Téléversement en cours…',
            textAlign: TextAlign.center,
            style: TextStyle(
              color:
                  Colors.white.withAlpha(204),
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 30),
          TextButton(
            onPressed: _cancelUpload,
            child: const Text(
              'Annuler',
              style: TextStyle(
                color: ReemColors.primary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    if (MediaQuery.sizeOf(context).width < 760) return _buildMobileEditor();

    return Column(
      children: [
        Expanded(
          child: _isTrimmerLoading
              ? const Center(
                  child:
                      CircularProgressIndicator(
                    color: ReemColors.primary,
                  ),
                )
              : _buildVideoPreview(),
        ),
        _buildBottomEditor(),
      ],
    );
  }


  // ---------------------------------------------------------------------------
  // ÉDITEUR TÉLÉPHONE (façon TikTok) : aperçu plein écran, outils à droite,
  // « Ta story » et « Suivant » en bas.
  // ---------------------------------------------------------------------------

  bool get _canGo => !_isSaving && !_isSending && _fileErrorMessage == null && !_isTrimmerLoading;

  Widget _roundTopButton(IconData icon, VoidCallback onTap, {bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: active ? ReemColors.primary.withValues(alpha: 0.85) : Colors.black45,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _sideTool(IconData icon, String label, VoidCallback onTap, {bool active = false}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                shadows: reemTextShadow,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: active ? ReemColors.primary : Colors.black38,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Icon(icon, color: Colors.white, size: 21),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileEditor() {
    final user = _sessionManager.currentUser;
    final photo = absoluteMediaUrl(user?['profile_photo_path']?.toString());
    final musicLabel = _musicPath == null ? 'Ajouter un son' : _getFileName(_musicPath!);

    return Container(
      color: const Color(0xFF06030F),
      child: SafeArea(
        child: Stack(
          children: [
            // Aperçu dans un cadre arrondi
            Positioned.fill(
              top: 62,
              bottom: 86,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: _isTrimmerLoading
                      ? const Center(child: CircularProgressIndicator(color: ReemColors.primary))
                      : _buildVideoPreview(),
                ),
              ),
            ),

            // Barre du haut
            Positioned(
              left: 12,
              right: 12,
              top: 8,
              child: Row(
                children: [
                  _roundTopButton(Icons.arrow_back_ios_new_rounded, () => Navigator.of(context).pop()),
                  Expanded(
                    child: Center(
                      child: GestureDetector(
                        onTap: _pickMusic,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 220),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.music_note_rounded, color: ReemColors.accent, size: 18),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  musicLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5),
                                ),
                              ),
                              if (_musicPath != null) ...[
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () => setState(() {
                                    _musicPath = null;
                                    _preparedVideoPath = null;
                                  }),
                                  child: const Icon(Icons.close_rounded, color: Colors.white70, size: 17),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _roundTopButton(
                    _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    () => setState(() {
                      _isMuted = !_isMuted;
                      _preparedVideoPath = null;
                    }),
                    active: _isMuted,
                  ),
                ],
              ),
            ),

            // Outils à droite
            Positioned(
              right: 14,
              top: 78,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _sideTool(Icons.content_cut_rounded, 'Modifier', _showTrimSheet),
                  _sideTool(Icons.crop_rotate_rounded, 'Recadrer', _showCropSheet, active: _cropFill),
                  _sideTool(Icons.auto_awesome_rounded, 'Filtres', _showFiltersSheet, active: _selectedFilterIndex != 0),
                  _sideTool(Icons.library_music_rounded, 'Musique', _pickMusic, active: _musicPath != null),
                  _sideTool(
                    _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    _isMuted ? 'Son coupé' : 'Son',
                    () => setState(() {
                      _isMuted = !_isMuted;
                      _preparedVideoPath = null;
                    }),
                    active: _isMuted,
                  ),
                ],
              ),
            ),

            // Barre du bas : Ta story + Suivant
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _canGo ? _postAsStory : null,
                      child: Container(
                        height: 54,
                        decoration: BoxDecoration(
                          color: ReemColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(gradient: ReemColors.gradient, shape: BoxShape.circle),
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: ReemColors.surface,
                                backgroundImage: photo != null ? NetworkImage(photo) : null,
                                child: photo == null
                                    ? const Icon(Icons.person_rounded, color: Colors.white70, size: 16)
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 9),
                            const Text(
                              'Ta story',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: _canGo ? _prepareFinalPreview : null,
                      child: Container(
                        height: 54,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: _canGo ? ReemColors.gradient : null,
                          color: _canGo ? null : ReemColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: _canGo
                              ? [BoxShadow(color: ReemColors.primary.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 4))]
                              : null,
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                              )
                            : const Text(
                                'Suivant',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Publie directement en story (30 s maximum).
  Future<void> _postAsStory() async {
    if (!_canGo) return;
    if ((_endValue - _startValue) > 30000) {
      _showErrorSnackBar('Une story dure 30 s maximum : raccourcis la vidéo avec « Modifier ».');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _player.pause();
      final outputPath = await _videoEditService.renderVideo(
        inputPath: _currentVideoPath,
        startMilliseconds: _startValue,
        endMilliseconds: _endValue,
        muteOriginal: _isMuted,
        filterName: _filters[_selectedFilterIndex]['name'] as String,
        musicPath: _musicPath,
        cropFill: _cropFill,
        zoom: _cropZoom,
        panX: _cropPanX,
        panY: _cropPanY,
      );
      final error = await StoryService().create(path: outputPath);
      if (!mounted) return;
      setState(() => _isSaving = false);
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Story publiée !')));
        Navigator.of(context).pop(true);
      } else {
        _showErrorSnackBar(error);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showErrorSnackBar('Impossible de publier la story : $e');
    }
  }

  Future<void> _showToolSheet({required String title, required Widget Function(StateSetter) builder}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            decoration: BoxDecoration(
              color: ReemColors.surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: ReemColors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(sheetContext),
                      child: const Icon(Icons.check_circle_rounded, color: ReemColors.primary, size: 28),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                builder(setSheet),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showTrimSheet() {
    return _showToolSheet(
      title: 'Modifier la durée',
      builder: (setSheet) {
        void both(VoidCallback fn) {
          setState(fn);
          setSheet(() {});
        }

        if (_videoDuration <= Duration.zero) {
          return const Text('Durée indisponible.', style: TextStyle(color: Colors.white70));
        }
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(_startValue.round()), style: const TextStyle(color: Colors.white70)),
                Text(
                  'Sélection : ${_formatDuration((_endValue - _startValue).round())}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
                Text(_formatDuration(_endValue.round()), style: const TextStyle(color: Colors.white70)),
              ],
            ),
            RangeSlider(
              min: 0,
              max: _videoDuration.inMilliseconds.toDouble(),
              divisions: _videoDuration.inMilliseconds > 1000 ? _videoDuration.inMilliseconds ~/ 500 : null,
              values: RangeValues(_startValue, _endValue),
              activeColor: ReemColors.primary,
              onChanged: (values) => both(() {
                _startValue = values.start;
                _endValue = values.end;
                _preparedVideoPath = null;
              }),
              onChangeEnd: (values) => _player.seek(Duration(milliseconds: values.start.round())),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCropSheet() {
    return _showToolSheet(
      title: 'Recadrer',
      builder: (setSheet) {
        void both(VoidCallback fn) {
          setState(fn);
          setSheet(() {});
        }

        Widget mode(String label, IconData icon, bool selected, VoidCallback onTap) {
          return Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  gradient: selected ? ReemColors.gradient : null,
                  color: selected ? null : ReemColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: Colors.white, size: 19),
                    const SizedBox(width: 7),
                    Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                mode('Ajuster', Icons.fit_screen_rounded, !_cropFill, () => both(() {
                      _cropFill = false;
                      _preparedVideoPath = null;
                    })),
                const SizedBox(width: 10),
                mode('Remplir', Icons.crop_free_rounded, _cropFill, () => both(() {
                      _cropFill = true;
                      _preparedVideoPath = null;
                    })),
              ],
            ),
            if (_cropFill) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.zoom_in_rounded, color: Colors.white70),
                  Expanded(
                    child: Slider(
                      min: 1,
                      max: 4,
                      value: _cropZoom,
                      activeColor: ReemColors.primary,
                      onChanged: (value) => both(() {
                        _cropZoom = value;
                        _preparedVideoPath = null;
                      }),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Recentrer',
                    icon: const Icon(Icons.restart_alt_rounded, color: Colors.white70),
                    onPressed: () => both(() {
                      _cropZoom = 1.0;
                      _cropPanX = 0.0;
                      _cropPanY = 0.0;
                      _preparedVideoPath = null;
                    }),
                  ),
                ],
              ),
              const Text(
                'Glisse sur la vidéo pour la déplacer, pince pour zoomer.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _showFiltersSheet() {
    return _showToolSheet(
      title: 'Filtres',
      builder: (setSheet) => SizedBox(
        height: 74,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _filters.length,
          itemBuilder: (context, index) {
            final selected = _selectedFilterIndex == index;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedFilterIndex = index;
                  _preparedVideoPath = null;
                });
                setSheet(() {});
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 72,
                margin: const EdgeInsets.only(right: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: selected ? ReemColors.gradient : null,
                  color: selected ? null : ReemColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${_filters[index]['name']}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Cadre 9:16 = exactement ce qui sera publié.
  /// "Ajuster" : vidéo entière. "Remplir" : on glisse / pince pour cadrer.
  Widget _buildCropFrame() {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final frameWidth = constraints.maxWidth;
          final frameHeight = constraints.maxHeight;
          final alignment = Alignment(_cropPanX, _cropPanY);

          final video = ColorFiltered(
            colorFilter: _filters[_selectedFilterIndex]['filter'],
            child: _cropFill
                ? OverflowBox(
                    alignment: alignment,
                    minWidth: frameWidth * _cropZoom,
                    maxWidth: frameWidth * _cropZoom,
                    minHeight: frameHeight * _cropZoom,
                    maxHeight: frameHeight * _cropZoom,
                    child: Video(
                      controller: _playerController,
                      controls: NoVideoControls,
                      fit: BoxFit.cover,
                      alignment: alignment,
                    ),
                  )
                : Video(
                    controller: _playerController,
                    controls: NoVideoControls,
                    fit: BoxFit.contain,
                  ),
          );

          return ClipRect(
            child: ColoredBox(
              color: Colors.black,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (_) => _gestureStartZoom = _cropZoom,
                onScaleUpdate: (details) {
                  if (!_cropFill) return;
                  setState(() {
                    _cropZoom =
                        (_gestureStartZoom * details.scale).clamp(1.0, 4.0).toDouble();
                    _cropPanX = (_cropPanX -
                            details.focalPointDelta.dx / (frameWidth / 2))
                        .clamp(-1.0, 1.0)
                        .toDouble();
                    _cropPanY = (_cropPanY -
                            details.focalPointDelta.dy / (frameHeight / 2))
                        .clamp(-1.0, 1.0)
                        .toDouble();
                    _preparedVideoPath = null;
                  });
                },
                child: video,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVideoPreview() {
    if (_fileErrorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _fileErrorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ReemColors.primary,
              fontSize: 15,
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        Container(
          color: const Color(0xFF111111),
          alignment: Alignment.center,
          child: _buildCropFrame(),
        ),

        Center(
          child: IconButton(
            icon: Icon(
              _isPlaying
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled,
                color:
                  Colors.white.withValues(alpha: 0.8),
              size: 60,
            ),
            onPressed: _toggleEditorPlayback,
          ),
        ),
      ],
    );
  }

  Widget _buildFinalPreview() {
    String? fileSize;
    final preparedPath = _preparedVideoPath;
    if (preparedPath != null) {
      try {
        final file = File(preparedPath);
        if (file.existsSync()) fileSize = _formatBytes(file.lengthSync());
      } catch (_) {}
    }
    final maxMs = _videoDuration.inMilliseconds.toDouble().clamp(1, double.infinity).toDouble();
    final positionMs = _videoPosition.inMilliseconds.toDouble().clamp(0, maxMs).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;

        if (wide) {
          // Ordinateur / grand écran : grand aperçu à gauche, formulaire à droite
          return Row(
            children: [
              Expanded(child: _bigPreview(maxMs, positionMs)),
              Container(
                width: 520,
                color: const Color(0xFF150E26),
                child: _finalForm(fileSize, cover: null),
              ),
            ],
          );
        }

        // Téléphone : description + petit aperçu en haut, boutons toujours visibles en bas
        return Container(
          color: const Color(0xFF150E26),
          child: _finalForm(fileSize, cover: _smallPreview()),
        );
      },
    );
  }

  /// Formulaire de publication défilant + barre d'actions fixe en bas.
  Widget _finalForm(String? fileSize, {required Widget? cover}) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PublishForm(
                  captionController: _descriptionController,
                  visibility: _visibility,
                  enabled: !_isSending,
                  cover: cover,
                  onVisibilityChanged: (value) => setState(() => _visibility = value),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.movie_creation_outlined, color: Colors.white54, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      [
                        _formatDuration(_videoDuration.inMilliseconds),
                        if (fileSize != null) fileSize,
                      ].join('  ·  '),
                      style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: Color(0xFF150E26),
            border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSending ? null : _returnToEditor,
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      label: const Text('Modifier'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: _isSaving || _isSending ? null : ReemColors.gradient,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _isSaving || _isSending ? null : _uploadVideoToLaravel,
                        icon: const Icon(Icons.publish_rounded),
                        label: const Text('Publier'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          disabledBackgroundColor: ReemColors.surfaceHigh,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Petit aperçu à droite de la description (toucher : lecture / pause).
  Widget _smallPreview() {
    return GestureDetector(
      onTap: () => _isPlaying ? _player.pause() : _player.play(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 96,
          height: 134,
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(controller: _playerController, controls: NoVideoControls, fit: BoxFit.cover),
              if (!_isPlaying)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  color: Colors.black54,
                  child: const Text(
                    'Aperçu',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Grand aperçu (version large) : toucher pour lire / mettre en pause.
  Widget _bigPreview(double maxMs, double positionMs) {
    return Container(
      width: double.infinity,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _isPlaying ? _player.pause() : _player.play(),
            child: Video(
              controller: _playerController,
              controls: NoVideoControls,
              fit: BoxFit.contain,
            ),
          ),
          if (!_isPlaying)
            IgnorePointer(
              child: Center(
                child: Icon(
                  Icons.play_circle_filled,
                  color: Colors.white.withValues(alpha: 0.8),
                  size: 64,
                ),
              ),
            ),
          Positioned(
            left: 4,
            right: 4,
            bottom: 0,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                min: 0,
                max: maxMs,
                value: positionMs,
                activeColor: Colors.white,
                inactiveColor: Colors.white30,
                onChanged: (value) => _player.seek(Duration(milliseconds: value.round())),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomEditor() {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.48,
      ),
      child: Container(
        color: const Color(0xFF150E26),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          SizedBox(
            height: 60,
            child: ListView.builder(
              scrollDirection:
                  Axis.horizontal,
              itemCount: _filters.length,
              itemBuilder:
                  (context, index) {
                final filter =
                    _filters[index];

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedFilterIndex =
                          index;
                      _preparedVideoPath = null;
                    });
                  },
                  child: Container(
                    width: 60,
                    margin:
                        const EdgeInsets.symmetric(
                      horizontal: 8,
                    ),
                    decoration:
                        BoxDecoration(
                      color: Colors.black38,
                      borderRadius:
                          BorderRadius.circular(8),
                      border:
                          _selectedFilterIndex ==
                                  index
                              ? Border.all(
                                  color:
                                      ReemColors.primary,
                                  width: 2,
                                )
                              : null,
                    ),
                    alignment:
                        Alignment.center,
                    child: Text(
                      filter['name'],
                      textAlign:
                          TextAlign.center,
                      style:
                          const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 10),

          // ---- Recadrage ----
          Row(
            children: [
              const Icon(Icons.crop_rotate, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Ajuster'),
                selected: !_cropFill,
                selectedColor: ReemColors.primary,
                backgroundColor: Colors.black38,
                labelStyle: const TextStyle(color: Colors.white),
                onSelected: (_) => setState(() {
                  _cropFill = false;
                  _preparedVideoPath = null;
                }),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Remplir'),
                selected: _cropFill,
                selectedColor: ReemColors.primary,
                backgroundColor: Colors.black38,
                labelStyle: const TextStyle(color: Colors.white),
                onSelected: (_) => setState(() {
                  _cropFill = true;
                  _preparedVideoPath = null;
                }),
              ),
              if (_cropFill) ...[
                Expanded(
                  child: Slider(
                    min: 1,
                    max: 4,
                    value: _cropZoom,
                    activeColor: ReemColors.primary,
                    onChanged: (value) => setState(() {
                      _cropZoom = value;
                      _preparedVideoPath = null;
                    }),
                  ),
                ),
                IconButton(
                  tooltip: 'Recentrer',
                  icon: const Icon(Icons.restart_alt, color: Colors.white70),
                  onPressed: () => setState(() {
                    _cropZoom = 1.0;
                    _cropPanX = 0.0;
                    _cropPanY = 0.0;
                    _preparedVideoPath = null;
                  }),
                ),
              ] else
                const Spacer(),
            ],
          ),
          if (_cropFill)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                'Glisse sur la vidéo pour la déplacer, pince ou utilise le curseur pour zoomer.',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),

          const SizedBox(height: 10),

          if (_videoDuration > Duration.zero) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(_startValue.round()), style: const TextStyle(color: Colors.white70)),
                Text('Durée sélectionnée : ${_formatDuration((_endValue - _startValue).round())}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                Text(_formatDuration(_endValue.round()), style: const TextStyle(color: Colors.white70)),
              ],
            ),
            RangeSlider(
              min: 0,
              max: _videoDuration.inMilliseconds.toDouble(),
              divisions: _videoDuration.inMilliseconds > 1000 ? _videoDuration.inMilliseconds ~/ 500 : null,
              values: RangeValues(_startValue, _endValue),
              activeColor: ReemColors.primary,
              onChanged: (values) {
                setState(() {
                  _startValue = values.start;
                  _endValue = values.end;
                  _preparedVideoPath = null;
                });
              },
              onChangeEnd: (values) => _player.seek(Duration(milliseconds: values.start.round())),
            ),
          ],

          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _isMuted = !_isMuted;
                    _preparedVideoPath = null;
                  }),
                  icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
                  label: Text(_isMuted ? 'Son original coupé' : 'Son original'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickMusic,
                  icon: const Icon(Icons.music_note),
                  label: Text(
                    _musicPath == null ? 'Ajouter musique' : _getFileName(_musicPath!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (_musicPath != null)
                IconButton(
                  tooltip: 'Retirer la musique',
                  onPressed: () => setState(() {
                    _musicPath = null;
                    _preparedVideoPath = null;
                  }),
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
            ],
          ),

          const SizedBox(height: 8),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style:
                  ElevatedButton.styleFrom(
                backgroundColor:
                    const Color(0xFF7C4DFF),
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(12),
                ),
                disabledBackgroundColor:
                    Colors.grey.shade800,
              ),
                onPressed: (_isSending || _isSaving || _fileErrorMessage != null)
                  ? null
                  : _prepareFinalPreview,
              child: _isSaving
                  ? const Text(
                      'Préparation...',
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    )
                    : const Text(
                      'Suivant',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
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
    );
  }
}

/// Classe permettant de suivre la progression
/// d'envoi d'un MultipartRequest.
class ProgressMultipartRequest
    extends http.MultipartRequest {
  final Function(
    int bytes,
    int totalBytes,
  ) onProgress;

  ProgressMultipartRequest(
    super.method,
    super.url, {
    required this.onProgress,
  });

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();

    final total = contentLength;

    int bytesSent = 0;

    final transformer =
        StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (
        List<int> data,
        EventSink<List<int>> sink,
      ) {
        bytesSent += data.length;

        onProgress(
          bytesSent,
          total,
        );

        sink.add(data);
      },
    );

    return http.ByteStream(
      byteStream.transform(transformer),
    );
  }
}