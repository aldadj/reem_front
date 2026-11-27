import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/reem_theme.dart';

/// Ouvre le recadrage et renvoie la photo recadrée (PNG carré), ou null si annulé.
Future<Uint8List?> cropProfilePhoto(BuildContext context, Uint8List bytes) {
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PhotoCropScreen(bytes: bytes),
    ),
  );
}

/// Recadrage de la photo de profil : on déplace et on zoome la photo
/// sous un cercle de visée, puis on valide. Fonctionne sur mobile et ordinateur.
class PhotoCropScreen extends StatefulWidget {
  const PhotoCropScreen({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  final TransformationController _transform = TransformationController();

  double? _imageWidth;
  double? _imageHeight;
  double _lastSide = 0;
  bool _saving = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _readSize();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _readSize() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() {
        _imageWidth = frame.image.width.toDouble();
        _imageHeight = frame.image.height.toDouble();
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _confirm(double side) async {
    setState(() => _saving = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      // Sortie d'environ 800 x 800 pixels
      final image = await boundary.toImage(pixelRatio: 800 / side);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted) return;
      Navigator.pop(context, data!.buffer.asUint8List());
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de recadrer cette photo.')),
      );
    }
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Recadrer la photo'),
      ),
      body: _failed
          ? const Center(
              child: Text('Cette image ne peut pas être lue.', style: TextStyle(color: Colors.white70)),
            )
          : _imageWidth == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(builder: (context, constraints) {
                  final side = (constraints.maxWidth < constraints.maxHeight - 160
                          ? constraints.maxWidth
                          : constraints.maxHeight - 160)
                      .clamp(200.0, 560.0);
                  return _buildCropper(side);
                }),
    );
  }

  Widget _buildCropper(double side) {
    final width = _imageWidth!;
    final height = _imageHeight!;

    // La photo est agrandie pour que son petit côté remplisse le carré
    final scale = side / (width < height ? width : height);
    final displayWidth = width * scale;
    final displayHeight = height * scale;

    // Position de départ : photo centrée
    if (_lastSide != side) {
      _lastSide = side;
      _transform.value = Matrix4.translationValues(
        -(displayWidth - side) / 2,
        -(displayHeight - side) / 2,
        0,
      );
    }

    return Column(
      children: [
        const SizedBox(height: 12),
        Expanded(
          child: Center(
            child: SizedBox(
              width: side,
              height: side,
              child: Stack(
                children: [
                  RepaintBoundary(
                    key: _boundaryKey,
                    child: ClipRect(
                      child: InteractiveViewer(
                        transformationController: _transform,
                        constrained: false,
                        minScale: 1,
                        maxScale: 6,
                        boundaryMargin: EdgeInsets.zero,
                        child: SizedBox(
                          width: displayWidth,
                          height: displayHeight,
                          child: Image.memory(widget.bytes, fit: BoxFit.fill, gaplessPlayback: true),
                        ),
                      ),
                    ),
                  ),
                  // Cercle de visée (ce qui est hors du cercle sera visible en rond de profil)
                  IgnorePointer(
                    child: CustomPaint(size: Size(side, side), painter: _CircleGuidePainter()),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 4, 24, 10),
          child: Text(
            'Déplace la photo avec le doigt (ou la souris) et pince ou utilise la molette pour zoomer.',
            textAlign: TextAlign.center,
            style: TextStyle(color: ReemColors.textMuted, fontSize: 12.5),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving ? null : () => _confirm(side),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Valider'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CircleGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    final circle = Path()
      ..addOval(Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - 2));
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, circle),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawPath(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
