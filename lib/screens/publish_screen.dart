import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:video_trimmer/video_trimmer.dart';

import '../services/auth_service.dart';
import '../services/session_manager.dart';

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

  final Trimmer _trimmer = Trimmer();

  double _startValue = 0.0;
  double _endValue = 0.0;

  bool _isTrimmerLoading = true;
  bool _isSaving = false;
  bool _isPlaying = false;
  bool _isSending = false;

  int _selectedFilterIndex = 0;

  double _uploadProgress = 0;

  String? _videoFileName;
  int? _videoFileSize;
  String? _fileErrorMessage;

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

      await _trimmer.loadVideo(
        videoFile: videoFile,
      );

      if (!mounted) return;

      // Met le volume à 100 %.
      try {
        await _trimmer.videoPlayerController?.setVolume(1.0);
      } catch (e) {
        debugPrint(
          'Impossible de régler le volume de la vidéo : $e',
        );
      }

      final duration =
          _trimmer.videoPlayerController?.value.duration;

      if (duration != null) {
        _endValue = duration.inMilliseconds.toDouble();
      }

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

  void _prepareVideoInfo() {
    final videoFile = File(_currentVideoPath);

    _videoFileName = _getFileName(_currentVideoPath);

    if (!videoFile.existsSync()) {
      _fileErrorMessage = 'Fichier vidéo introuvable.';
      _videoFileSize = null;
      return;
    }

    _videoFileSize = videoFile.lengthSync();

    if (_videoFileSize != null &&
        _videoFileSize! > _maxVideoBytes) {
      _fileErrorMessage =
          'La vidéo dépasse la taille maximale de 100 Mo.';
    } else {
      _fileErrorMessage = null;
    }

    debugPrint(
      '🎥 Vidéo : $_videoFileName',
    );

    debugPrint(
      '📦 Taille : ${_videoFileSize != null ? _formatBytes(_videoFileSize!) : "inconnue"}',
    );
  }

  /// Prépare la vidéo découpée puis l'envoie à Laravel.
  ///
  /// Les filtres sont actuellement uniquement visuels dans l'aperçu.
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

    if (_endValue <= _startValue) {
      _showErrorSnackBar(
        'La durée sélectionnée de la vidéo est invalide.',
      );
      return;
    }

    if (!mounted) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await _trimmer.saveTrimmedVideo(
        startValue: _startValue,
        endValue: _endValue,
        onSave: (outputPath) {
          if (!mounted) return;

          if (outputPath == null || outputPath.isEmpty) {
            setState(() {
              _isSaving = false;
            });

            _showErrorSnackBar(
              'Impossible de préparer la vidéo.',
            );

            return;
          }

          debugPrint(
            '✅ Vidéo découpée : $outputPath',
          );

          setState(() {
            _isSaving = false;
          });

          // Le fichier découpé est envoyé directement.
          // Aucun FFmpeg n'est nécessaire.
          _performUpload(outputPath);
        },
      );
    } catch (e) {
      debugPrint(
        '❌ Erreur lors du découpage : $e',
      );

      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      _showErrorSnackBar(
        'Impossible de préparer la vidéo : $e',
      );
    }
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
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
      body: _isSending
          ? _buildUploadProgress()
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
        ColorFiltered(
          colorFilter:
              _filters[_selectedFilterIndex]
                  ['filter'],
          child: VideoViewer(
            trimmer: _trimmer,
          ),
        ),

        Center(
          child: IconButton(
            icon: Icon(
              _isPlaying
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled,
              color:
                  Colors.white.withOpacity(0.8),
              size: 60,
            ),
            onPressed: () async {
              try {
                final playbackState =
                    await _trimmer
                        .videoPlaybackControl(
                  startValue: _startValue,
                  endValue: _endValue,
                );

                if (!mounted) return;

                setState(() {
                  _isPlaying = playbackState;
                });
              } catch (e) {
                debugPrint(
                  'Erreur lecture vidéo : $e',
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBottomEditor() {
    return Container(
      color: const Color(0xFF0F1628),
      padding: const EdgeInsets.all(16),
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

          if (!_isTrimmerLoading)
            TrimViewer(
              trimmer: _trimmer,
              viewerHeight: 50,
              viewerWidth:
                  MediaQuery.of(context)
                      .size
                      .width,
              durationStyle:
                  DurationStyle.FORMAT_MM_SS,
              onChangeStart: (value) {
                _startValue = value;
              },
              onChangeEnd: (value) {
                _endValue = value;
              },
              onChangePlaybackState:
                  (value) {
                if (!mounted) return;

                setState(() {
                  _isPlaying = value;
                });
              },
            ),

          const SizedBox(height: 16),

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

          const SizedBox(height: 16),

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
              onPressed:
                  (_isSending ||
                          _isSaving ||
                          _fileErrorMessage !=
                              null)
                      ? null
                      : _uploadVideoToLaravel,
              child: _isSaving
                  ? const Text(
                      'Préparation...',
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Publier',
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