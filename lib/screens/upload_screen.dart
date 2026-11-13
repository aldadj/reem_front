import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'publish_launcher.dart';
import '../services/video_edit_service.dart';

/// Écran de création façon TikTok :
/// caméra plein écran, bouton d'enregistrement central, retourner la caméra,
/// flash, import depuis la galerie (vidéo ou photos).
/// Après le tournage ou l'import, l'éditeur s'ouvre et la vidéo démarre seule
/// (recadrage de durée, filtres, musique...).
class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen>
    with WidgetsBindingObserver {
  static const int _maxSeconds = 60;
  static const _videoExtensions = {
    'mp4', 'mov', 'avi', 'mkv', 'm4v', '3gp', 'webm',
  };
  static const _imageExtensions = {
    'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif',
  };

  final VideoEditService _videoEditService = VideoEditService();

  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;

  bool _isInitializing = true;
  bool _isRecording = false;
  bool _isBusy = false;
  bool _torchOn = false;
  bool _isProcessing = false;
  String _processingLabel = 'Création de la vidéo…';
  int _seconds = 0;
  Timer? _timer;

  bool get _supportsCamera {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.windows);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_supportsCamera) {
      _initializeCamera();
    } else {
      _isInitializing = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_supportsCamera) return;
    if (state == AppLifecycleState.inactive) {
      _timer?.cancel();
      final old = _controller;
      _controller = null;
      _isRecording = false;
      _seconds = 0;
      if (mounted) setState(() {});
      old?.dispose();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initializeCamera();
    }
  }

  // ---------------------------------------------------------------------------
  // CAMÉRA
  // ---------------------------------------------------------------------------

  Future<void> _initializeCamera() async {
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (!mounted) return;
      if (_cameras.isEmpty) {
        setState(() => _isInitializing = false);
        return;
      }

      final controller = CameraController(
        _cameras[_cameraIndex],
        ResolutionPreset.high,
        enableAudio: true,
      );
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {}

      setState(() {
        _controller = controller;
        _torchOn = false;
        _isInitializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isInitializing = false);
      _showMessage('Impossible d’ouvrir la caméra : $e');
    }
  }

  Future<void> _flipCamera() async {
    if (_isRecording || _isBusy || _cameras.length < 2) return;
    _isBusy = true;
    try {
      final current = _cameras[_cameraIndex].lensDirection;
      var next = _cameras.indexWhere((c) => c.lensDirection != current);
      if (next < 0) next = (_cameraIndex + 1) % _cameras.length;

      final old = _controller;
      setState(() {
        _controller = null;
        _cameraIndex = next;
      });
      await old?.dispose();
      await _initializeCamera();
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final next = !_torchOn;
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torchOn = next);
    } catch (_) {
      _showMessage('Flash indisponible sur cette caméra.');
    }
  }

  Future<void> _toggleRecording() async {
    if (_isBusy) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      _showMessage('Caméra non prête');
      return;
    }

    _isBusy = true;
    try {
      if (_isRecording) {
        await _stopRecording();
      } else {
        await controller.startVideoRecording();
        if (!mounted) return;
        setState(() {
          _isRecording = true;
          _seconds = 0;
        });
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() => _seconds++);
          if (_seconds >= _maxSeconds && !_isBusy) {
            _isBusy = true;
            _stopRecording().whenComplete(() => _isBusy = false);
          }
        });
      }
    } catch (e) {
      _showMessage('Erreur caméra : $e');
    } finally {
      _isBusy = false;
    }
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final controller = _controller;
    if (controller == null || !_isRecording) return;

    try {
      final file = await controller.stopVideoRecording();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _seconds = 0;
      });
      openPublishScreen(context: context, videoPath: file.path);
    } catch (e) {
      if (mounted) {
        setState(() => _isRecording = false);
        _showMessage('Erreur : $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // IMPORT GALERIE (vidéo ou photos)
  // ---------------------------------------------------------------------------

  String _extensionOf(PlatformFile file) {
    final name = file.name.toLowerCase();
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1);
  }

  Future<void> _importFromGallery() async {
    if (_isRecording || _isProcessing) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: kIsWeb ? FileType.video : FileType.media,
        allowMultiple: !kIsWeb,
        withData: kIsWeb,
      );
      if (!mounted || result == null || result.files.isEmpty) return;

      // Web : une seule vidéo, envoyée avec ses octets.
      if (kIsWeb) {
        final file = result.files.first;
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) {
          _showMessage('Impossible de lire la vidéo sélectionnée.');
          return;
        }
        openPublishScreen(
          context: context,
          videoBytes: bytes,
          fileName: file.name,
        );
        return;
      }

      final videos = <PlatformFile>[];
      final images = <PlatformFile>[];
      for (final file in result.files) {
        if (file.path == null) continue;
        final ext = _extensionOf(file);
        if (_videoExtensions.contains(ext)) {
          videos.add(file);
        } else if (_imageExtensions.contains(ext)) {
          images.add(file);
        }
      }

      final total = videos.length + images.length;
      if (total == 0) {
        _showMessage('Format non pris en charge.');
        return;
      }
      if (total > 12) {
        _showMessage('Sélectionne 12 médias maximum.');
        return;
      }

      // Une seule vidéo -> éditeur directement (lecture automatique)
      if (videos.length == 1 && images.isEmpty) {
        openPublishScreen(context: context, videoPath: videos.first.path!);
        return;
      }

      // Plusieurs médias -> une seule vidéo, dans l'ordre de sélection
      final String mergedPath;
      if (videos.isEmpty) {
        setState(() {
          _processingLabel = 'Création du diaporama…';
          _isProcessing = true;
        });
        mergedPath = await _videoEditService
            .createSlideshow(images.map((f) => f.path!).toList());
      } else {
        setState(() {
          _processingLabel = 'Fusion des médias…';
          _isProcessing = true;
        });
        final ordered = [
          for (final file in result.files)
            if (file.path != null &&
                (_videoExtensions.contains(_extensionOf(file)) ||
                    _imageExtensions.contains(_extensionOf(file))))
              file.path!,
        ];
        mergedPath = await _videoEditService.mergeMedia(ordered);
      }
      if (!mounted) return;
      openPublishScreen(context: context, videoPath: mergedPath);
    } catch (e) {
      _showMessage('Import impossible : $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  String _clock(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackground(),
          // Dégradés pour garder les boutons lisibles
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x99000000),
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0xB3000000),
                  ],
                  stops: [0, 0.2, 0.7, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _buildSideTools(),
                  ),
                ),
                _buildBottomBar(),
              ],
            ),
          ),
          if (_isProcessing)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(_processingLabel,
                          style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    final controller = _controller;

    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (_supportsCamera && controller != null && controller.value.isInitialized) {
      final preview = controller.value.previewSize;
      if (preview == null) return CameraPreview(controller);

      // Aperçu en plein écran (portrait), recadré comme TikTok
      final w = math.min(preview.width, preview.height);
      final h = math.max(preview.width, preview.height);
      return ClipRect(
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: w,
              height: h,
              child: CameraPreview(controller),
            ),
          ),
        ),
      );
    }

    // Pas de caméra (web, bureau sans caméra...) : on propose l'import
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E1530), Color(0xFF060816)],
        ),
      ),
      child: Center(
        child: Icon(Icons.video_library_outlined,
            color: Colors.white54, size: 72),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isRecording ? 1 : 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _clock(_seconds),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 48), // équilibre visuel avec le bouton fermer
        ],
      ),
    );
  }

  Widget _buildSideTools() {
    if (!_supportsCamera || _controller == null) return const SizedBox.shrink();

    Widget tool(IconData icon, String label, VoidCallback? onTap,
        {bool active = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: active ? const Color(0xFFFFD54F) : Colors.white,
                  size: 30),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          tool(
            Icons.flip_camera_ios_outlined,
            'Retourner',
            _isRecording || _cameras.length < 2 ? null : _flipCamera,
          ),
          tool(
            _torchOn ? Icons.flash_on : Icons.flash_off,
            'Flash',
            _toggleTorch,
            active: _torchOn,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_supportsCamera)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                _isRecording
                    ? 'Appuie pour arrêter'
                    : 'Appuie pour filmer · $_maxSeconds s max',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ),
          if (_supportsCamera)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Espace à gauche pour centrer le bouton d'enregistrement
                const SizedBox(width: 72),
                _buildRecordButton(),
                _buildImportButton(),
              ],
            )
          else
            Center(child: _buildImportButton()),
        ],
      ),
    );
  }

  Widget _buildRecordButton() {
    return GestureDetector(
      onTap: _toggleRecording,
      child: SizedBox(
        width: 92,
        height: 92,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 92,
              height: 92,
              child: CircularProgressIndicator(
                value: _isRecording ? _seconds / _maxSeconds : 1,
                strokeWidth: 5,
                color: _isRecording ? Colors.redAccent : Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: _isRecording ? 38 : 68,
              height: _isRecording ? 38 : 68,
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(_isRecording ? 8 : 34),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportButton() {
    return GestureDetector(
      onTap: _importFromGallery,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.photo_library_rounded,
                  color: Colors.black87, size: 26),
            ),
            const SizedBox(height: 4),
            const Text(
              'Importer',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
