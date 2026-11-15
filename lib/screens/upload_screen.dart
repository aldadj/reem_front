import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import 'publish_launcher.dart';
import '../services/video_edit_service.dart';
import '../theme/reem_theme.dart';

enum _CaptureMode { video, photo }

/// Écran de création façon TikTok.
///  - la caméra s'ouvre tout de suite (vidéo ou photo) ;
///  - en bas, une ligne avec les vidéos du téléphone (le « + » ouvre toute la galerie) ;
///  - après le tournage ou l'import, l'éditeur s'ouvre et la vidéo démarre seule.
class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> with WidgetsBindingObserver {
  static const int _maxSeconds = 60;
  static const int _maxItems = 12;
  static const int _pageSize = 24;
  static const _videoExtensions = {'mp4', 'mov', 'avi', 'mkv', 'm4v', '3gp', 'webm'};
  static const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'};

  final VideoEditService _videoEditService = VideoEditService();

  // Caméra
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  _CaptureMode _mode = _CaptureMode.video;
  bool _isInitializing = true;
  bool _isRecording = false;
  bool _isBusy = false;
  bool _torchOn = false;
  int _seconds = 0;
  Timer? _timer;

  // Traitement (fusion, diaporama...)
  bool _isProcessing = false;
  String _processingLabel = 'Création de la vidéo…';

  // Galerie du téléphone
  AssetPathEntity? _videoAlbum;
  List<AssetEntity> _assets = [];
  bool _galleryDenied = false;

  bool get _supportsCamera {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.windows);
  }

  bool get _supportsGallery {
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
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
    if (_supportsGallery) _loadGallery();
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _onShutterTap() async {
    if (_mode == _CaptureMode.photo) {
      await _takePhoto();
    } else {
      await _toggleRecording();
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

  // Photo : l'image devient une courte vidéo, modifiable comme les autres
  Future<void> _takePhoto() async {
    if (_isBusy) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      _showMessage('Caméra non prête');
      return;
    }

    _isBusy = true;
    try {
      final picture = await controller.takePicture();
      if (!mounted) return;
      setState(() {
        _processingLabel = 'Préparation de la photo…';
        _isProcessing = true;
      });
      final path = await _videoEditService.createSlideshow([picture.path]);
      if (!mounted) return;
      openPublishScreen(context: context, videoPath: path);
    } catch (e) {
      _showMessage('Photo impossible : $e');
    } finally {
      _isBusy = false;
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ---------------------------------------------------------------------------
  // GALERIE DU TÉLÉPHONE
  // ---------------------------------------------------------------------------

  Future<void> _loadGallery() async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess) {
        if (mounted) setState(() => _galleryDenied = true);
        return;
      }

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        onlyAll: true,
      );
      if (albums.isEmpty) {
        if (mounted) setState(() => _assets = []);
        return;
      }

      final first = await albums.first.getAssetListPaged(page: 0, size: _pageSize);
      if (!mounted) return;
      setState(() {
        _galleryDenied = false;
        _videoAlbum = albums.first;
        _assets = first;
      });
    } catch (_) {
      if (mounted) setState(() => _galleryDenied = true);
    }
  }

  Future<void> _askGalleryAccess() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (permission.hasAccess) {
      await _loadGallery();
    } else {
      await PhotoManager.openSetting();
    }
  }

  Future<void> _openGallerySheet() async {
    if (_isRecording || _isProcessing) return;

    if (!_supportsGallery) {
      await _importFromFiles();
      return;
    }
    if (_galleryDenied || _videoAlbum == null) {
      await _askGalleryAccess();
      if (_videoAlbum == null) return;
    }
    if (!mounted) return;

    final result = await showModalBottomSheet<_PickerResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: ReemColors.background,
      builder: (_) => _GalleryPickerSheet(
        album: _videoAlbum!,
        firstPage: _assets,
        pageSize: _pageSize,
        maxItems: _maxItems,
      ),
    );
    if (!mounted || result == null) return;

    if (result.useFiles) {
      await _importFromFiles();
    } else if (result.assets.isNotEmpty) {
      await _importAssets(result.assets);
    }
  }

  Future<void> _importAssets(List<AssetEntity> assets) async {
    if (_isProcessing) return;
    setState(() {
      _processingLabel = 'Préparation…';
      _isProcessing = true;
    });
    try {
      final paths = <String>[];
      for (final asset in assets) {
        final file = await asset.originFile;
        if (file != null) paths.add(file.path);
      }
      if (paths.isEmpty) {
        _showMessage('Impossible de lire cette vidéo.');
        return;
      }
      if (!mounted) return;

      if (paths.length == 1) {
        openPublishScreen(context: context, videoPath: paths.first);
        return;
      }

      setState(() => _processingLabel = 'Fusion des vidéos…');
      final merged = await _videoEditService.mergeMedia(paths);
      if (!mounted) return;
      openPublishScreen(context: context, videoPath: merged);
    } catch (e) {
      _showMessage('Import impossible : $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ---------------------------------------------------------------------------
  // IMPORT PAR FICHIERS (web, ordinateur, ou autres dossiers)
  // ---------------------------------------------------------------------------

  String _extensionOf(PlatformFile file) {
    final name = file.name.toLowerCase();
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1);
  }

  Future<void> _importFromFiles() async {
    if (_isRecording || _isProcessing) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: kIsWeb ? FileType.video : FileType.media,
        allowMultiple: !kIsWeb,
        withData: kIsWeb,
      );
      if (!mounted || result == null || result.files.isEmpty) return;

      if (kIsWeb) {
        final file = result.files.first;
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) {
          _showMessage('Impossible de lire la vidéo sélectionnée.');
          return;
        }
        openPublishScreen(context: context, videoBytes: bytes, fileName: file.name);
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
      if (total > _maxItems) {
        _showMessage('Sélectionne $_maxItems médias maximum.');
        return;
      }

      if (videos.length == 1 && images.isEmpty) {
        openPublishScreen(context: context, videoPath: videos.first.path!);
        return;
      }

      final String mergedPath;
      if (videos.isEmpty) {
        setState(() {
          _processingLabel = 'Création du diaporama…';
          _isProcessing = true;
        });
        mergedPath = await _videoEditService.createSlideshow(images.map((f) => f.path!).toList());
      } else {
        setState(() {
          _processingLabel = 'Fusion des médias…';
          _isProcessing = true;
        });
        final ordered = [
          for (final file in result.files)
            if (file.path != null &&
                (_videoExtensions.contains(_extensionOf(file)) || _imageExtensions.contains(_extensionOf(file))))
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
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0xCC000000)],
                  stops: [0, 0.18, 0.55, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: Align(alignment: Alignment.centerRight, child: _buildSideTools()),
                ),
                _buildBottomArea(),
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
                      Text(_processingLabel, style: const TextStyle(color: Colors.white)),
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

      final w = math.min(preview.width, preview.height);
      final h = math.max(preview.width, preview.height);
      return ClipRect(
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(width: w, height: h, child: CameraPreview(controller)),
          ),
        ),
      );
    }

    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E1530), Color(0xFF060816)],
        ),
      ),
      child: Center(child: Icon(Icons.video_library_outlined, color: Colors.white54, size: 72)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    _clock(_seconds),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildSideTools() {
    if (!_supportsCamera || _controller == null) return const SizedBox.shrink();

    Widget tool(IconData icon, String label, VoidCallback? onTap, {bool active = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: active ? ReemColors.gold : Colors.white, size: 30, shadows: reemTextShadow),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  shadows: reemTextShadow,
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
          tool(Icons.flip_camera_ios_outlined, 'Retourner', _isRecording || _cameras.length < 2 ? null : _flipCamera),
          tool(_torchOn ? Icons.flash_on : Icons.flash_off, 'Flash', _toggleTorch, active: _torchOn),
        ],
      ),
    );
  }

  Widget _buildBottomArea() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_supportsCamera) ...[
            _buildModeSwitch(),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 72),
                  _buildShutter(),
                  _buildGalleryButton(),
                ],
              ),
            ),
          ] else
            Center(child: _buildGalleryButton()),
          if (_supportsGallery && !_isRecording) ...[
            const SizedBox(height: 16),
            _buildGalleryStrip(),
          ],
        ],
      ),
    );
  }

  Widget _buildModeSwitch() {
    Widget option(_CaptureMode mode, String label) {
      final selected = _mode == mode;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _isRecording ? null : () => setState(() => _mode = mode),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white60,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 14,
                  letterSpacing: 1,
                  shadows: reemTextShadow,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: selected ? 18 : 0,
                height: 3,
                decoration: BoxDecoration(gradient: ReemColors.gradient, borderRadius: BorderRadius.circular(2)),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [option(_CaptureMode.video, 'VIDÉO'), option(_CaptureMode.photo, 'PHOTO')],
    );
  }

  Widget _buildShutter() {
    final isPhoto = _mode == _CaptureMode.photo;
    return GestureDetector(
      onTap: _onShutterTap,
      child: SizedBox(
        width: 88,
        height: 88,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 88,
              height: 88,
              child: CircularProgressIndicator(
                value: _isRecording ? _seconds / _maxSeconds : 1,
                strokeWidth: 5,
                color: _isRecording ? Colors.redAccent : Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: _isRecording ? 36 : 66,
              height: _isRecording ? 36 : 66,
              decoration: BoxDecoration(
                color: isPhoto ? Colors.white : Colors.redAccent,
                borderRadius: BorderRadius.circular(_isRecording ? 8 : 33),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryButton() {
    return GestureDetector(
      onTap: _openGallerySheet,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.photo_library_rounded, color: Colors.black87, size: 25),
            ),
            const SizedBox(height: 4),
            const Text(
              'Importer',
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, shadows: reemTextShadow),
            ),
          ],
        ),
      ),
    );
  }

  // Une seule ligne : les vidéos récentes du téléphone, puis un « + »
  Widget _buildGalleryStrip() {
    if (_galleryDenied) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextButton.icon(
          onPressed: _askGalleryAccess,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.black45,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          icon: const Icon(Icons.photo_library_outlined, size: 20),
          label: const Text('Autoriser l’accès à tes vidéos'),
        ),
      );
    }

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _assets.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          if (index == _assets.length) {
            return GestureDetector(
              onTap: _openGallerySheet,
              child: Container(
                width: 64,
                height: 96,
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white54, width: 1.2),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 30),
                    SizedBox(height: 2),
                    Text('Voir +', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            );
          }
          final asset = _assets[index];
          return GestureDetector(
            onTap: () => _importAssets([asset]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 64, height: 96, child: _AssetThumb(asset: asset)),
            ),
          );
        },
      ),
    );
  }
}

class _PickerResult {
  const _PickerResult({this.assets = const [], this.useFiles = false});

  final List<AssetEntity> assets;
  final bool useFiles;
}

/// Miniature d'une vidéo du téléphone, avec sa durée.
class _AssetThumb extends StatefulWidget {
  const _AssetThumb({required this.asset});

  final AssetEntity asset;

  @override
  State<_AssetThumb> createState() => _AssetThumbState();
}

class _AssetThumbState extends State<_AssetThumb> {
  late final Future<Uint8List?> _thumb;

  @override
  void initState() {
    super.initState();
    _thumb = widget.asset.thumbnailDataWithSize(ThumbnailSize(260, 400));
  }

  String _duration() {
    final d = widget.asset.videoDuration;
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FutureBuilder<Uint8List?>(
          future: _thumb,
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data == null) return const ColoredBox(color: ReemColors.surfaceHigh);
            return Image.memory(data, fit: BoxFit.cover, gaplessPlayback: true);
          },
        ),
        Positioned(
          left: 4,
          bottom: 3,
          child: Text(
            _duration(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              shadows: reemTextShadow,
            ),
          ),
        ),
      ],
    );
  }
}

/// Galerie complète (le « + ») : défilement infini, sélection de plusieurs vidéos.
class _GalleryPickerSheet extends StatefulWidget {
  const _GalleryPickerSheet({
    required this.album,
    required this.firstPage,
    required this.pageSize,
    required this.maxItems,
  });

  final AssetPathEntity album;
  final List<AssetEntity> firstPage;
  final int pageSize;
  final int maxItems;

  @override
  State<_GalleryPickerSheet> createState() => _GalleryPickerSheetState();
}

class _GalleryPickerSheetState extends State<_GalleryPickerSheet> {
  final ScrollController _scroll = ScrollController();
  late final List<AssetEntity> _assets = [...widget.firstPage];
  final List<AssetEntity> _selected = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _hasMore = widget.firstPage.length >= widget.pageSize;
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) _loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    _loading = true;
    try {
      final next = await widget.album.getAssetListPaged(page: _page, size: widget.pageSize);
      if (!mounted) return;
      setState(() {
        _assets.addAll(next);
        _page++;
        _hasMore = next.length >= widget.pageSize;
      });
    } finally {
      _loading = false;
    }
  }

  void _toggle(AssetEntity asset) {
    setState(() {
      if (_selected.contains(asset)) {
        _selected.remove(asset);
      } else if (_selected.length < widget.maxItems) {
        _selected.add(asset);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(
                child: Text(
                  'Tes vidéos',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, const _PickerResult(useFiles: true)),
                child: const Text('Fichiers…'),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Touche une vidéo pour la sélectionner. Plusieurs vidéos sont assemblées dans l’ordre.',
              style: TextStyle(color: ReemColors.textMuted, fontSize: 12.5),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _assets.isEmpty
              ? const Center(child: Text('Aucune vidéo trouvée.', style: TextStyle(color: ReemColors.textMuted)))
              : GridView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(2),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                    childAspectRatio: 0.7,
                  ),
                  itemCount: _assets.length,
                  itemBuilder: (context, index) {
                    final asset = _assets[index];
                    final order = _selected.indexOf(asset);
                    return GestureDetector(
                      onTap: () => _toggle(asset),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _AssetThumb(asset: asset),
                          if (order >= 0) Container(color: ReemColors.primary.withValues(alpha: 0.35)),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: order >= 0 ? ReemColors.primary : Colors.black38,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: order >= 0
                                  ? Text(
                                      '${order + 1}',
                                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, _PickerResult(assets: List.of(_selected))),
                child: Text(_selected.isEmpty ? 'Choisis une vidéo' : 'Importer (${_selected.length})'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
