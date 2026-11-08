import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/auth_service.dart';
import '../services/session_manager.dart';
import '../services/video_edit_service.dart';

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
  final TextEditingController _titleController = TextEditingController();

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

    if (_titleController.text.trim().isEmpty) {
      _showErrorSnackBar(
        'Veuillez donner un titre à votre Reel !',
      );
      return;
    }

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
    if (_titleController.text.trim().isEmpty) {
      _showErrorSnackBar(
        'Veuillez donner un titre à votre Reel !',
      );
      return;
    }

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

      request.fields['title'] =
          _titleController.text.trim();

      request.fields['description'] =
          _titleController.text.trim();

      request.fields['caption'] =
          _titleController.text.trim();

      request.fields['visibility'] =
          'public';

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

        String message =
            'Échec de la publication.';

        try {
          final body =
              jsonDecode(response.body);

          if (body is Map &&
              body['message'] is String) {
            message = body['message'];
          } else if (body is Map) {
            message = body.toString();
          }
        } catch (_) {
          if (response.body.isNotEmpty) {
            message = response.body;
          }
        }

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

    _titleController.dispose();

    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playingSubscription?.cancel();
    _player.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060816),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _isFinalPreview ? 'Aperçu avant publication' : 'Modifier la vidéo',
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
          onPressed: () {
            Navigator.of(context).pop();
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
                    Colors.redAccent,
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
                color: Colors.redAccent,
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
    return Column(
      children: [
        Expanded(
          child: _isTrimmerLoading
              ? const Center(
                  child:
                      CircularProgressIndicator(
                    color: Colors.redAccent,
                  ),
                )
              : _buildVideoPreview(),
        ),
        _buildBottomEditor(),
      ],
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
              color: Colors.redAccent,
              fontSize: 15,
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        Container(
          color: const Color(0xFF333333),
          alignment: Alignment.center,
          child: ColorFiltered(
            colorFilter: _filters[_selectedFilterIndex]['filter'],
            child: Video(
              controller: _playerController,
              controls: NoVideoControls,
              fit: BoxFit.contain,
            ),
          ),
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
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            color: const Color(0xFF333333),
            alignment: Alignment.center,
            child: Video(
              controller: _playerController,
              controls: NoVideoControls,
              fit: BoxFit.contain,
            ),
          ),
        ),
        Container(
          color: const Color(0xFF0F1628),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            children: [
              Slider(
                min: 0,
                max: _videoDuration.inMilliseconds.toDouble().clamp(1, double.infinity),
                value: _videoPosition.inMilliseconds.toDouble().clamp(
                      0,
                      _videoDuration.inMilliseconds.toDouble().clamp(1, double.infinity),
                    ),
                activeColor: Colors.redAccent,
                onChanged: (value) => _player.seek(Duration(milliseconds: value.round())),
              ),
              Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: _isPlaying ? 'Pause' : 'Lire',
                      icon: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 32,
                      ),
                      onPressed: () => _isPlaying ? _player.pause() : _player.play(),
                    ),
                    const Text('Aperçu final', style: TextStyle(color: Colors.white70)),
                  ],
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _returnToEditor,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Modifier'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _uploadVideoToLaravel,
                      icon: const Icon(Icons.publish),
                      label: const Text('Publier'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C4DFF),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomEditor() {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.48,
      ),
      child: Container(
        color: const Color(0xFF0F1628),
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
                                      Colors.redAccent,
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

          const SizedBox(height: 16),

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
              activeColor: Colors.redAccent,
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

          TextField(
            controller: _titleController,
            style: const TextStyle(
              color: Colors.white,
            ),
            decoration: InputDecoration(
              hintText:
                  'Ajoutez une légende...',
              hintStyle: TextStyle(
                color: Colors.grey[600],
              ),
              filled: true,
              fillColor:
                  const Color(0xFF1A1A2E),
              border:
                  OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(12),
                borderSide:
                    BorderSide.none,
              ),
            ),
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
                      'Prévisualiser',
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