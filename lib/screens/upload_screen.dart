import 'dart:io';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'publish_launcher.dart';
import '../services/video_edit_service.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() =>
      _UploadScreenState();
}

class _UploadScreenState
    extends State<UploadScreen> {
  CameraController? _controller;

  bool _isInitializing = true;
  bool _isRecording = false;
  bool _isProcessingPhotos = false;
  final VideoEditService _videoEditService = VideoEditService();

  bool get _supportsCamera {
    return !kIsWeb &&
        (defaultTargetPlatform ==
                TargetPlatform.android ||
            defaultTargetPlatform ==
                TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.windows);
  }

  @override
  void initState() {
    super.initState();

    if (kIsWeb) {
      // Sur Web, on utilise directement
      // le sélecteur de fichiers.
      _isInitializing = false;
    } else {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      if (!_supportsCamera) {
        if (!mounted) return;

        setState(() {
          _isInitializing = false;
        });

        return;
      }

      final cameras =
          await availableCameras();

      if (!mounted || cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _isInitializing = false;
          });
        }

        return;
      }

      final controller =
          CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: true,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isInitializing = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isInitializing = false;
      });

      _showMessage(
        'Impossible d’ouvrir la caméra : $e',
      );
    }
  }

  Future<void> _startOrStopCapture() async {
    if (_controller == null ||
        !_controller!.value.isInitialized) {
      _showMessage(
        'Caméra non prête',
      );

      return;
    }

    if (_isRecording) {
      try {
        final file =
            await _controller!
                .stopVideoRecording();

        if (!mounted) return;

        openPublishScreen(
          context: context,
          videoPath: file.path,
        );
      } catch (e) {
        if (!mounted) return;

        _showMessage(
          'Erreur : $e',
        );
      }
    } else {
      try {
        await _controller!
            .startVideoRecording();

        if (!mounted) return;

        setState(() {
          _isRecording = true;
        });
      } catch (e) {
        if (!mounted) return;

        _showMessage(
          'Impossible de démarrer : $e',
        );
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      final result =
          await FilePicker.platform.pickFiles(
        type: FileType.video,

        // Sur Web, on récupère les bytes.
        // Sur Android, on conserve surtout
        // le chemin local.
        withData: kIsWeb,
      );

      if (!mounted || result == null) {
        return;
      }

      final file =
          result.files.single;

      if (kIsWeb) {
        final bytes = file.bytes;

        if (bytes == null ||
            bytes.isEmpty) {
          _showMessage(
            'Impossible de lire la vidéo sélectionnée.',
          );

          return;
        }

        debugPrint(
          '🌐 Vidéo Web sélectionnée : ${file.name}',
        );

        debugPrint(
          '📦 Taille : ${bytes.length} octets',
        );

        openPublishScreen(
          context: context,
          videoBytes: bytes,
          fileName: file.name,
        );

        return;
      }

      // Android / iOS
      final path = file.path;

      if (path == null ||
          path.isEmpty) {
        _showMessage(
          'Impossible de récupérer le fichier vidéo.',
        );

        return;
      }

      debugPrint(
        '📱 Vidéo mobile sélectionnée : $path',
      );

      openPublishScreen(
        context: context,
        videoPath: path,
      );
    } catch (e) {
      debugPrint(
        '❌ Erreur sélection vidéo : $e',
      );

      if (!mounted) return;

      _showMessage(
        'Impossible de sélectionner la vidéo : $e',
      );
    }
  }

  Future<void> _showMediaPicker() async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.video_library_outlined, color: Colors.white),
              title: const Text('Importer une vidéo', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'video'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Colors.white),
              title: const Text('Créer une vidéo avec des photos', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'photos'),
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;
    if (selection == 'video') await _pickVideo();
    if (selection == 'photos') await _pickPhotos();
  }

  Future<void> _pickPhotos() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      if (!mounted || result == null) return;
      if (result.files.length > 12) {
        _showMessage('Sélectionnez au maximum 12 photos.');
        return;
      }

      setState(() => _isProcessingPhotos = true);
      final tempDirectory = await getTemporaryDirectory();
      final imagePaths = <String>[];

      for (var index = 0; index < result.files.length; index++) {
        final file = result.files[index];
        var path = file.path;
        if (path == null || !File(path).existsSync()) {
          final bytes = file.bytes;
          if (bytes == null || bytes.isEmpty) continue;
          final extension = file.extension ?? 'jpg';
          path = '${tempDirectory.path}${Platform.pathSeparator}'
              'reem_photo_${DateTime.now().microsecondsSinceEpoch}_$index.$extension';
          await File(path).writeAsBytes(bytes, flush: true);
        }
        imagePaths.add(path);
      }

      if (imagePaths.isEmpty) {
        throw Exception('Aucune photo n’a pu être lue.');
      }

      final slideshowPath = await _videoEditService.createSlideshow(imagePaths);
      if (!mounted) return;
      openPublishScreen(context: context, videoPath: slideshowPath);
    } catch (e) {
      if (mounted) _showMessage('Impossible de créer la vidéo : $e');
    } finally {
      if (mounted) setState(() => _isProcessingPhotos = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFF060816),
      body: SafeArea(
        child: Stack(
          children: [
            // =========================
            // ARRIÈRE-PLAN
            // =========================

            Container(
              decoration:
                  const BoxDecoration(
                gradient:
                    LinearGradient(
                  begin:
                      Alignment.topCenter,
                  end:
                      Alignment.bottomCenter,
                  colors: [
                    Color(0xFF0E1530),
                    Color(0xFF060816),
                  ],
                ),
              ),

              child: _buildMainContent(),
            ),

            if (_isProcessingPhotos)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 16),
                        Text('Création de la vidéo…', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),

            // =========================
            // BARRE DU HAUT
            // =========================

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AppBar(
                backgroundColor:
                    Colors.transparent,
                elevation: 0,
                leading:
                    IconButton(
                  icon:
                      const Icon(
                    Icons.close,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pop();
                  },
                ),
                title:
                    const Text(
                  'Nouveau reel',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                centerTitle: true,
              ),
            ),

            // =========================
            // GALERIE
            // =========================

            Positioned(
              bottom: 24,
              left: 20,
              child:
                  GestureDetector(
                onTap: _showMediaPicker,
                child:
                    Container(
                  width: 62,
                  height: 62,
                  decoration:
                      BoxDecoration(
                    color:
                        Colors.white.withValues(
                      alpha: 0.92,
                    ),
                    shape:
                        BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color:
                            Colors.black.withValues(
                          alpha: 0.25,
                        ),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child:
                      const Icon(
                    Icons.photo_library,
                    color: Colors.black,
                    size: 28,
                  ),
                ),
              ),
            ),

            // =========================
            // BOUTON CAMÉRA
            // =========================

            if (_supportsCamera)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child:
                      GestureDetector(
                    onTap:
                        _startOrStopCapture,
                    child:
                        Container(
                      width: 92,
                      height: 92,
                      decoration:
                          BoxDecoration(
                        shape:
                            BoxShape.circle,
                        color:
                            _isRecording
                                ? Colors.redAccent
                                : Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color:
                                Colors.redAccent.withValues(
                              alpha: 0.35,
                            ),
                            blurRadius: 18,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child:
                          Icon(
                        _isRecording
                            ? Icons.stop
                            : Icons.add,
                        size: 42,
                        color:
                            Colors.black,
                      ),
                    ),
                  ),
                ),
              ),

            // =========================
            // TEXTE DU BAS
            // =========================

            Positioned(
              bottom: 36,
              right: 24,
              child:
                  Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      Colors.black54,
                  borderRadius:
                      BorderRadius.circular(
                    20,
                  ),
                ),
                child:
                    Text(
                    !_supportsCamera
                      ? 'Importer une vidéo ou des photos'
                      : (_isRecording
                          ? 'Enregistrement…'
                          : 'Prêt à publier'),
                  style:
                      const TextStyle(
                    color: Colors.white,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    if (!_supportsCamera) {
      return Center(
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.video_library_outlined,
              color:
                  Colors.white70,
              size: 90,
            ),
            const SizedBox(
              height: 20,
            ),
            const Text(
              'Publier un Reel',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 10,
            ),
            const Text(
              'Sélectionnez une vidéo ou plusieurs photos.',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                color: Colors.white60,
                fontSize: 15,
              ),
            ),
            const SizedBox(
              height: 28,
            ),
            ElevatedButton.icon(
              onPressed: _showMediaPicker,
              icon:
                  const Icon(
                Icons.video_library,
              ),
              label:
                  const Text(
                'Choisir un média',
              ),
              style:
                  ElevatedButton.styleFrom(
                backgroundColor:
                    const Color(
                  0xFF7C4DFF,
                ),
                foregroundColor:
                    Colors.white,
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 15,
                ),
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_isInitializing) {
      return const Center(
        child:
            CircularProgressIndicator(
          color:
              Color(0xFF7C4DFF),
        ),
      );
    }

    if (_controller != null) {
      return CameraPreview(
        _controller!,
      );
    }

    return const Center(
      child: Text(
        'Caméra indisponible',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 18,
        ),
      ),
    );
  }
}