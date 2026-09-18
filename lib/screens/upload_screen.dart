import 'dart:io';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'publish_screen.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  CameraController? _controller;
  bool _isInitializing = true;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      // On vérifie si on est sur une plateforme mobile avant d'appeler availableCameras()
      List<CameraDescription> cameras = [];
      if (Platform.isAndroid || Platform.isIOS) {
        cameras = await availableCameras();
      } else {
        // Sur Windows, Mac, Linux, on sait que ça ne marchera pas.
        print("La fonctionnalité de caméra n'est pas supportée sur cette plateforme.");
      }

      if (!mounted || cameras.isEmpty) {
        setState(() => _isInitializing = false);
        return;
      }

      final controller = CameraController(cameras.first, ResolutionPreset.high, enableAudio: true);
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
      setState(() => _isInitializing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d’ouvrir la caméra : $e')),
      );
    }
  }

  Future<void> _startOrStopCapture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Caméra non prête')));
      return;
    }

    if (_isRecording) {
      try {
        final file = await _controller!.stopVideoRecording();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => PublishScreen(videoPath: file.path)),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    } else {
      try {
        await _controller!.startVideoRecording();
        setState(() => _isRecording = true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Impossible de démarrer : $e')));
      }
    }
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (!mounted) return;

    if (result != null && result.files.single.path != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => PublishScreen(videoPath: result.files.single.path!)),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060816),
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0E1530), Color(0xFF060816)],
                ),
              ),
              child: _isInitializing
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF7C4DFF)))
                  : _controller != null
                      ? CameraPreview(_controller!)
                      : const Center(child: Text('Caméra indisponible', style: TextStyle(color: Colors.white70, fontSize: 18))),
            ),
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: const Text('Nouveau reel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                centerTitle: true,
              ),
            ),
            Positioned(
              bottom: 24,
              left: 20,
              child: GestureDetector(
                onTap: _pickVideo,
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 10)],
                  ),
                  child: const Icon(Icons.photo_library, color: Colors.black, size: 28),
                ),
              ),
            ),
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _startOrStopCapture,
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRecording ? Colors.redAccent : Colors.white,
                      boxShadow: [BoxShadow(color: Colors.redAccent.withValues(alpha: 0.35), blurRadius: 18, spreadRadius: 4)],
                    ),
                    child: Icon(_isRecording ? Icons.stop : Icons.add, size: 42, color: Colors.black),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 36,
              right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isRecording ? 'Enregistrement…' : 'Prêt à publier',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
