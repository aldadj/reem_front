import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_trimmer/video_trimmer.dart';

class VideoTrimScreen extends StatefulWidget {
  final String videoPath;

  const VideoTrimScreen({super.key, required this.videoPath});

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  final Trimmer _trimmer = Trimmer();
  double _startValue = 0.0;
  double _endValue = 0.0;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _loadVideo();
  }

  Future<void> _loadVideo() async {
    await _trimmer.loadVideo(videoFile: File(widget.videoPath));
    final duration = _trimmer.videoPlayerController?.value.duration;
    if (duration != null) {
      _endValue = duration.inMilliseconds.toDouble();
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveTrimmedVideo() async {
    setState(() {
      _isSaving = true;
    });

    await _trimmer.saveTrimmedVideo(
      startValue: _startValue,
      endValue: _endValue,
      onSave: (outputPath) {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
          if (outputPath != null && outputPath.isNotEmpty) {
            Navigator.pop(context, outputPath);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Impossible de sauvegarder le clip.')), 
            );
          }
        }
      },
    );
  }

  @override
  void dispose() {
    _trimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Recadrer la vidéo'),
        backgroundColor: Colors.black,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  if (_isSaving)
                    const LinearProgressIndicator(color: Colors.redAccent),
                  if (_isSaving) const SizedBox(height: 14),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: VideoViewer(trimmer: _trimmer)),
                        const SizedBox(height: 12),
                        TrimViewer(
                          trimmer: _trimmer,
                          viewerHeight: 50.0,
                          viewerWidth: MediaQuery.of(context).size.width,
                          durationStyle: DurationStyle.FORMAT_MM_SS,
                          onChangeStart: (value) => _startValue = value,
                          onChangeEnd: (value) => _endValue = value,
                          onChangePlaybackState: (value) {
                            setState(() {
                              _isPlaying = value;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: Icon(
                                _isPlaying ? Icons.pause_circle : Icons.play_circle,
                                color: Colors.white,
                                size: 42,
                              ),
                              onPressed: () async {
                                final playbackState = await _trimmer.videoPlaybackControl(
                                  startValue: _startValue,
                                  endValue: _endValue,
                                );
                                setState(() {
                                  _isPlaying = playbackState;
                                });
                              },
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Début: ${Duration(milliseconds: _startValue.toInt()).inSeconds}s  •  Fin: ${Duration(milliseconds: _endValue.toInt()).inSeconds}s',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _isSaving ? null : _saveTrimmedVideo,
                      child: const Text(
                        'Enregistrer l’extrait sélectionné',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text(
                      'Annuler',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
