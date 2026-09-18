import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_editor/video_editor.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:reem_front/screens/publish_screen.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.videoFile});
  final File videoFile;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class StickerState {
  StickerState(this.assetPath, {required this.position, this.scale = 1.0, this.rotation = 0.0});
  final String assetPath;
  Offset position;
  double scale;
  double rotation;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final VideoEditorController _controller;
  bool _isExporting = false;
  String _overlayText = '';
  final TextEditingController _textEditingController = TextEditingController();
  // Nouveaux états pour la position du texte
  Offset _textPosition = Offset.zero;
  bool _isTextPositionInitialized = false;
  double _textScale = 1.0;
  double _baseScale = 1.0;
  double _textRotation = 0.0;
  double _baseRotation = 0.0;
  final GlobalKey _videoViewerKey = GlobalKey();
  // Nouveaux états pour le style du texte
  Color _textColor = Colors.white;
  String _fontFamily = 'Roboto'; // Police par défaut

  // Liste des polices disponibles
  final Map<String, String> _fonts = {
    'Roboto': 'Roboto', // Police système par défaut
    'Lato': 'Lato',
    'Oswald': 'Oswald',
  };

  // Liste des couleurs prédéfinies
  final List<Color> _colors = [Colors.white, Colors.black, Colors.red, Colors.blue, Colors.green, Colors.yellow, Colors.purple];

  // Nouveaux états pour les autocollants
  final List<StickerState> _stickers = [];
  int? _activeStickerIndex;

  // Liste des autocollants disponibles (assurez-vous que ces fichiers existent)
  final List<String> _stickerAssets = ['assets/stickers/cool.png', 'assets/stickers/love.png'];

  @override
  void initState() {
    super.initState();
    _controller = VideoEditorController.file(
      widget.videoFile,
      minDuration: const Duration(seconds: 1),
      maxDuration: const Duration(minutes: 10), // Limite à 10 minutes par exemple
    );
    _controller
        .initialize(
          // Règle le volume à 100%
          videoOptions: (controller) => controller.setVolume(1.0),
        )
        .then((_) => setState(() {}))
        .catchError((error) {
          // Gère les erreurs d'initialisation
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Impossible de charger cette vidéo. Veuillez en choisir une autre."),
                backgroundColor: Colors.red,
              ),
            );
          }
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    _textEditingController.dispose();
    super.dispose();
  }

  Future<void> _exportVideo() async {
    setState(() => _isExporting = true);

    final config = _controller.exportConfig;
    final tempDir = await getTemporaryDirectory();
    final outputPath = '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.mp4';

    // Dimensions de la vidéo et de l'aperçu
    final videoSize = _controller.video.value.size;
    final viewerSize = _videoViewerKey.currentContext?.size;

    String command;
    String filterComplex = "";
    if (_overlayText.trim().isNotEmpty) {
      // Calculer les coordonnées x et y pour FFmpeg
      double x = 0, y = 0;
      if (viewerSize != null && viewerSize.width > 0 && viewerSize.height > 0) {
        // Convertit la position de l'UI (pixels logiques) en position vidéo (pixels réels)
        x = (_textPosition.dx / viewerSize.width) * videoSize.width;
        y = (_textPosition.dy / viewerSize.height) * videoSize.height;
      } else {
        // Fallback au centre si la taille n'est pas disponible
        x = (videoSize.width / 2);
        y = (videoSize.height / 2);
      }

      // Calcule la taille de la police en fonction de l'échelle
      final baseFontSize = 48;
      final scaledFontSize = (baseFontSize * _textScale).round();

      // Convertit la rotation de radians (UI) en degrés (FFmpeg)
      final rotationDegrees = _textRotation * 180 / 3.1415926535;

      // Convertit la couleur en format hexadécimal pour FFmpeg (0xRRGGBB)
      final colorHex = '0x${_textColor.value.toRadixString(16).substring(2)}';

      // Prépare le chemin de la police pour FFmpeg
      String fontPathOption = '';
      if (_fontFamily != 'Roboto') {
        // Pour les polices personnalisées, nous devons fournir le chemin du fichier
        // Note : Cela suppose que les polices sont dans assets/fonts/
        fontPathOption = ":fontfile=assets/fonts/${_fontFamily}-Regular.ttf";
      }

      // Si du texte est ajouté, on doit ré-encoder la vidéo.
      final sanitizedText = _overlayText.replaceAll("'", "’"); // Échapper les apostrophes
      filterComplex += 'drawtext=text=\'$sanitizedText\':fontcolor=$colorHex$fontPathOption:fontsize=$scaledFontSize:box=1:boxcolor=black@0.5:boxborderw=5:x=$x-text_w/2:y=$y-text_h/2,rotate=$rotationDegrees*PI/180:c=none';
    }

    if (_stickers.isNotEmpty && viewerSize != null) {
      String stickerOverlays = "";
      String inputs = "";
      for (int i = 0; i < _stickers.length; i++) {
        final sticker = _stickers[i];
        inputs += '-i "${sticker.assetPath}" ';
        final stickerX = (sticker.position.dx / viewerSize.width) * videoSize.width;
        final stickerY = (sticker.position.dy / viewerSize.height) * videoSize.height;
        final stickerRotation = sticker.rotation; // en radians

        // [1:v] est le premier sticker, [2:v] le deuxième, etc.
        // [v$i] est une variable pour la sortie de chaque étape
        final lastOutput = i == 0 ? "0:v" : "v${i - 1}";
        final currentOutput = "v$i";
        stickerOverlays +=
            '[$lastOutput][${i + 1}:v] overlay=$stickerX:$stickerY:eval=frame [${currentOutput}];';
      }
      filterComplex = stickerOverlays;
      command = '-i "${_controller.file.path}" $inputs -ss ${_controller.startTrim} -to ${_controller.endTrim} -filter_complex "$filterComplex" -map "[v${_stickers.length - 1}]" -map 0:a? -preset ultrafast -y "$outputPath"';
      // On combine les filtres de texte (s'il y en a) et de stickers
      command = '-i "${_controller.file.path}" $inputs -ss ${_controller.startTrim} -to ${_controller.endTrim} -filter_complex "${filterComplex.isNotEmpty ? '$filterComplex,' : ''}$stickerOverlays" -map "[v${_stickers.length - 1}]" -map 0:a? -c:a copy -preset ultrafast -y "$outputPath"';
    } else if (_overlayText.trim().isNotEmpty) {
       command = '-i "${_controller.file.path}" -ss ${_controller.startTrim} -to ${_controller.endTrim} -vf "$filterComplex" -preset ultrafast -y "$outputPath"';
       command = '-i "${_controller.file.path}" -ss ${_controller.startTrim} -to ${_controller.endTrim} -vf "$filterComplex" -c:a copy -preset ultrafast -y "$outputPath"';
    } else {
      // S'il n'y a pas de texte, on utilise la commande rapide sans ré-encodage.
      command = '-i "${_controller.file.path}" -ss ${_controller.startTrim} -to ${_controller.endTrim} -c copy "$outputPath"';
    }

    final session = await FFmpegKit.execute(command);

    setState(() => _isExporting = false);

    final returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode)) {
      // La vidéo a été exportée avec succès
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => PublishScreen(videoPath: outputPath),
        ),
      );
    } else {
      // Gérer l'erreur
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de l\'exportation de la vidéo.')),
      );
    }
  }

  void _showAddTextDialog() {
    _textEditingController.text = _overlayText;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Ajouter du texte"),
        content: TextField(
          controller: _textEditingController,
          autofocus: true,
          decoration: const InputDecoration(hintText: "Votre texte ici..."),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _overlayText = '');
              _textEditingController.clear();
              Navigator.pop(context);
            },
            child: const Text("Effacer"),
          ),
          TextButton(
            onPressed: () {
              setState(() => _overlayText = _textEditingController.text);
              Navigator.pop(context);
            },
            child: const Text("Valider"),
          ),
        ],
      ),
    );
  }

  void _showStickerGallery() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          itemCount: _stickerAssets.length,
          itemBuilder: (context, index) {
            final asset = _stickerAssets[index];
            return GestureDetector(
              onTap: () {
                final viewerSize = _videoViewerKey.currentContext?.size;
                if (viewerSize == null) return;

                setState(() {
                  _stickers.add(StickerState(
                    asset,
                    position: Offset(viewerSize.width / 2, viewerSize.height / 2),
                  ));
                });
                Navigator.pop(context);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Image.asset(asset),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Éditeur Vidéo"),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            onPressed: _isExporting ? null : _exportVideo,
            icon: _isExporting
                ? const CircularProgressIndicator(color: Colors.white)
                : const Icon(Icons.check),
          )
        ],
      ),
      body: _controller.initialized
          ? SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(builder: (context, constraints) {
                      // Initialise la position du texte au centre la première fois
                      if (!_isTextPositionInitialized) {
                        _textPosition = Offset(
                          constraints.maxWidth / 2,
                          constraints.maxHeight / 2,
                        );
                        _isTextPositionInitialized = true;
                      }

                      return Stack(
                        key: _videoViewerKey,
                        alignment: Alignment.center,
                        children: [
                          CropGridViewer.preview(controller: _controller),
                          // Affichage des autocollants
                          ..._stickers.asMap().entries.map((entry) {
                            final index = entry.key;
                            final sticker = entry.value;
                            return Positioned(
                              left: sticker.position.dx,
                              top: sticker.position.dy,
                              child: GestureDetector(
                                onScaleStart: (details) => setState(() => _activeStickerIndex = index),
                                onScaleUpdate: (details) {
                                  if (_activeStickerIndex != index) return;
                                  setState(() {
                                    sticker.rotation += details.rotation;
                                    sticker.scale *= details.scale;
                                    sticker.position += details.focalPointDelta;
                                  });
                                },
                                onScaleEnd: (details) => setState(() => _activeStickerIndex = null),
                                child: Transform.rotate(
                                  angle: sticker.rotation,
                                  child: Transform.scale(scale: sticker.scale, child: Image.asset(sticker.assetPath, width: 100)),
                                ),
                              ),
                            );
                          }),
                          if (_overlayText.isNotEmpty)
                            Positioned(
                              left: _textPosition.dx,
                              top: _textPosition.dy,
                              child: GestureDetector(
                                onScaleStart: (details) {
                                  // Sauvegarde l'état initial au début du geste
                                  _baseScale = _textScale;
                                  _baseRotation = _textRotation;
                                },
                                onScaleUpdate: (details) {
                                  setState(() {
                                    // Gère le redimensionnement (pincement)
                                    _textScale = (_baseScale * details.scale).clamp(0.5, 3.0);
                                    // Gère la rotation
                                    _textRotation = _baseRotation + details.rotation;
                                    // Gère le déplacement
                                    _textPosition += details.focalPointDelta;
                                  });
                                },
                                child: Transform.rotate(
                                  angle: _textRotation,
                                  child: Transform.scale(scale: _textScale, child: _buildOverlayText()),
                                ),
                              ),
                            ),
                        ],
                      );
                    }),
                  ),
                  // Barre d'outils pour le découpage et le texte
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    color: Colors.black.withOpacity(0.5),
                    child: Column(
                      children: [
                        TrimSlider(
                          controller: _controller,
                          height: 40,
                          horizontalMargin: 16.0,
                        ),
                        // Barre d'outils pour le texte
                        if (_overlayText.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          // Sélecteur de couleur
                          SizedBox(
                            height: 40,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _colors.length,
                              itemBuilder: (context, index) => GestureDetector(
                                onTap: () => setState(() => _textColor = _colors[index]),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 8),
                                  width: 40,
                                  decoration: BoxDecoration(
                                    color: _colors[index],
                                    shape: BoxShape.circle,
                                    border: Border.all(color: _textColor == _colors[index] ? Colors.white : Colors.transparent, width: 2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Sélecteur de police
                          SizedBox(
                            height: 40,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _fonts.length,
                              itemBuilder: (context, index) {
                                final fontName = _fonts.keys.elementAt(index);
                                return TextButton(
                                  onPressed: () => setState(() => _fontFamily = fontName),
                                  child: Text(fontName, style: TextStyle(fontFamily: _fonts[fontName], color: _fontFamily == fontName ? Colors.redAccent : Colors.white)),
                                );
                              },
                            ),
                          ),
                        ],
                        TrimSlider(
                          controller: _controller,
                          height: 60,
                          horizontalMargin: 16.0,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Column(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.text_fields, color: Colors.white),
                                  onPressed: _showAddTextDialog,
                                ),
                                const Text("Texte", style: TextStyle(color: Colors.white)),
                              ],
                            ),
                            Column(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.sticky_note_2_outlined, color: Colors.white),
                                  onPressed: _showStickerGallery,
                                ),
                                const Text("Stickers", style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildOverlayText() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        _overlayText,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _textColor,
          fontFamily: _fontFamily,
          fontSize: 24, // La taille ici est pour l'UI, elle est indépendante de l'échelle
        ),
      ),
    );
  }
}