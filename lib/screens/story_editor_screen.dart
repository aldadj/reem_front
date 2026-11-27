
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/video_edit_service.dart';
import '../theme/reem_theme.dart';
import 'story_preview_screen.dart';

class StoryEditorScreen extends StatefulWidget {
  const StoryEditorScreen({
    super.key,
    this.path,
    this.bytes,
    this.fileName,
    required this.isVideo,
  });

  final String? path;
  final Uint8List? bytes;
  final String? fileName;
  final bool isVideo;

  @override
  State<StoryEditorScreen> createState() => _StoryEditorScreenState();
}

class _StoryEditorScreenState extends State<StoryEditorScreen> {
  final VideoEditService _editService = VideoEditService();

  VideoPlayerController? _player;
  String? _workingPath;

  bool _loading = true;
  bool _rendering = false;
  bool _mute = false;

  String _filter = 'Naturel';

  double _start = 0;
  double _end = 0;

  Duration _duration = Duration.zero;

  static const List<String> _filters = [
    'Naturel',
    'Gris',
    'Sépia',
    'Vintage',
    'Froid',
    'Chaud',
  ];

  @override
  void initState() {
    super.initState();
    _initializeEditor();
  }

  Future<void> _initializeEditor() async {
    try {
      if (!widget.isVideo) {
        if (!kIsWeb && widget.path != null) {
          _workingPath = await _editService.createSlideshow([widget.path!]);
          await _initializePlayerFromPath(_workingPath!);
        } else {
          if (mounted) setState(() => _loading = false);
        }
        return;
      }

      if (!kIsWeb && widget.path != null) {
        _workingPath = widget.path;
        await _initializePlayerFromPath(widget.path!);
      } else if (kIsWeb && widget.bytes != null) {
        final uri = Uri.dataFromBytes(
          widget.bytes!,
          mimeType: _mimeType(widget.fileName),
        );

        final player = VideoPlayerController.networkUrl(uri);
        await player.initialize();
        await player.setLooping(true);

        if (!mounted) {
          await player.dispose();
          return;
        }

        setState(() {
          _player = player;
          _duration = player.value.duration;
          _end = _duration.inMilliseconds.toDouble();
          _loading = false;
        });

        await player.play();
      } else {
        throw Exception('Impossible de charger cette vidéo.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('Impossible de charger le média : $e');
    }
  }

  String _mimeType(String? name) {
    final extension = name?.split('.').last.toLowerCase();

    switch (extension) {
      case 'webm':
        return 'video/webm';
      case 'mov':
        return 'video/quicktime';
      case 'm4v':
        return 'video/x-m4v';
      case 'mp4':
      default:
        return 'video/mp4';
    }
  }

  Future<void> _initializePlayerFromPath(String path) async {
    final player = VideoPlayerController.file(File(path));
    await player.initialize();
    await player.setLooping(true);

    if (!mounted) {
      await player.dispose();
      return;
    }

    setState(() {
      _player = player;
      _duration = player.value.duration;
      _end = _duration.inMilliseconds.toDouble();
      _loading = false;
    });

    await player.play();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _formatTime(double milliseconds) {
    final seconds = (milliseconds / 1000).floor();
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;

    return '$minutes:${remaining.toString().padLeft(2, '0')}';
  }

  ColorFilter? _previewFilter() {
    switch (_filter) {
      case 'Gris':
        return const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case 'Sépia':
      case 'Vintage':
        return const ColorFilter.matrix([
          0.393, 0.769, 0.189, 0, 0,
          0.349, 0.686, 0.168, 0, 0,
          0.272, 0.534, 0.131, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case 'Froid':
        return const ColorFilter.matrix([
          0.9, 0, 0, 0, 0,
          0, 1, 0, 0, 0,
          0, 0, 1.1, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case 'Chaud':
        return const ColorFilter.matrix([
          1.1, 0, 0, 0, 0,
          0, 1, 0, 0, 0,
          0, 0, 0.9, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      default:
        return null;
    }
  }

  Future<void> _togglePlayback() async {
    final player = _player;
    if (player == null) return;

    if (player.value.isPlaying) {
      await player.pause();
    } else {
      if (player.value.position >= Duration(milliseconds: _end.round())) {
        await player.seekTo(Duration(milliseconds: _start.round()));
      }
      await player.play();
    }

    if (mounted) setState(() {});
  }

  Future<void> _renderAndContinue() async {
    if (kIsWeb) {
      _message(
        'Le rendu vidéo Web sera activé avec le moteur de montage navigateur.',
      );
      return;
    }

    if (_workingPath == null) {
      _message('Aucun fichier vidéo disponible pour le montage.');
      return;
    }

    if (_end <= _start) {
      _message('Choisis une durée de découpage valide.');
      return;
    }

    setState(() => _rendering = true);

    try {
      await _player?.pause();

      final output = await _editService.renderVideo(
        inputPath: _workingPath!,
        startMilliseconds: _start,
        endMilliseconds: _end,
        muteOriginal: _mute,
        filterName: _filter,
      );

      if (!mounted) return;

      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => StoryPreviewScreen(
            path: output,
            isVideo: true,
          ),
        ),
      );

      if (result == true && mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _message('Erreur pendant le montage : $e');
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  Future<void> _continueImage() async {
    if (widget.bytes == null && widget.path == null) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => StoryPreviewScreen(
          path: widget.path,
          bytes: widget.bytes,
          fileName: widget.fileName,
          isVideo: false,
        ),
      ),
    );

    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Widget _buildMediaPreview() {
    final player = _player;

    if (player != null && player.value.isInitialized) {
      return GestureDetector(
        onTap: _togglePlayback,
        child: Center(
          child: AspectRatio(
            aspectRatio: player.value.aspectRatio,
            child: ColorFiltered(
              colorFilter: _previewFilter() ??
                  const ColorFilter.mode(
                    Colors.transparent,
                    BlendMode.dst,
                  ),
              child: VideoPlayer(player),
            ),
          ),
        ),
      );
    }

    if (!widget.isVideo) {
      if (widget.bytes != null) {
        return Image.memory(widget.bytes!, fit: BoxFit.contain);
      }

      if (!kIsWeb && widget.path != null) {
        return Image.file(File(widget.path!), fit: BoxFit.contain);
      }
    }

    return const Center(
      child: Icon(
        Icons.video_library_outlined,
        color: Colors.white54,
        size: 70,
      ),
    );
  }

  Widget _buildTrimControls() {
    if (_player == null || _duration.inMilliseconds <= 0) {
      return const SizedBox.shrink();
    }

    final maximum = _duration.inMilliseconds.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DÉCOUPAGE',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatTime(_start),
              style: const TextStyle(color: Colors.white70),
            ),
            Text(
              _formatTime(_end),
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
        RangeSlider(
          min: 0,
          max: maximum,
          values: RangeValues(_start, _end),
          activeColor: ReemColors.primary,
          inactiveColor: Colors.white24,
          onChanged: (values) {
            setState(() {
              _start = values.start;
              _end = values.end;
            });

            _player?.seekTo(
              Duration(milliseconds: values.start.round()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'FILTRES',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _filters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final filter = _filters[index];
              final selected = filter == _filter;

              return ChoiceChip(
                label: Text(filter),
                selected: selected,
                selectedColor: ReemColors.primary,
                backgroundColor: const Color(0xFF292929),
                labelStyle: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (_) {
                  setState(() => _filter = filter);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text(
          'Modifier la Story',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Son original',
            onPressed: () => setState(() => _mute = !_mute),
            icon: Icon(
              _mute ? Icons.volume_off : Icons.volume_up,
              color: _mute ? ReemColors.accent : Colors.white,
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: ReemColors.accent),
            )
          : Column(
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151515),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _buildMediaPreview(),
                        if (_player != null)
                          IconButton(
                            onPressed: _togglePlayback,
                            iconSize: 58,
                            color: Colors.white,
                            icon: Icon(
                              _player!.value.isPlaying
                                  ? Icons.pause_circle
                                  : Icons.play_circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (widget.isVideo) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: _buildTrimControls(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                    child: _buildFilters(),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ReemColors.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                      onPressed: _rendering
                          ? null
                          : widget.isVideo
                              ? _renderAndContinue
                              : _continueImage,
                      child: _rendering
                          ? const CircularProgressIndicator(
                              color: Colors.white,
                            )
                          : const Text(
                              'Continuer  →',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
