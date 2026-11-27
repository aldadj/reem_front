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
      // Affiche un indicateur de chargement pendant le chargement de la vidéo
          ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  if (_isSaving)
                  // Affiche une barre de progression pendant l'enregistrement du clip
                    const LinearProgressIndicator(color: Colors.redAccent),
                  if (_isSaving) const SizedBox(height: 14),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: VideoViewer(trimmer: _trimmer)),
                        const SizedBox(height: 25),// Espace entre le VideoViewer et le TrimViewer
                        TrimViewer(
                          trimmer: _trimmer, // Widget permettant de sélectionner la portion de la vidéo à recadrer
                          viewerHeight: 50.0, // Hauteur du TrimViewer
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
                        // Affiche les boutons de lecture/pause et les temps de début/fin sélectionnés
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: Icon(
                                _isPlaying ? Icons.pause_circle : Icons.play_circle,
                                color: Colors.white,
                                size: 40, // Taille de l'icône du bouton de lecture/pause
                              ),
                              onPressed: () async {
                                final playbackState = await _trimmer.videoPlaybackControl(
                                  startValue: _startValue,
                                  endValue: _endValue,
                                );
                                setState(() {
                                  _isPlaying = playbackState; // Met à jour l'état de lecture après le contrôle de la lecture
                                });
                              },
                            ),
                            const SizedBox(width: 12), // Espace entre le bouton de lecture/pause et le texte des temps
                            Text(
                              'Début: ${Duration(milliseconds: _startValue.toInt()).inSeconds}s  •  Fin: ${Duration(milliseconds: _endValue.toInt()).inSeconds}s',// Texte affichant les temps de début et de fin sélectionnés
                              style: const TextStyle(color: Colors.white70), // Style du texte des temps de début/fin
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Affiche le bouton pour enregistrer le clip sélectionné et un bouton pour annuler
                  const SizedBox(height: 12), // Espace entre le TrimViewer et le bouton d'enregistrement
                  SizedBox(
                    width: double.infinity,
                    height: 50, // Hauteur du bouton pour enregistrer le clip sélectionné
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent, // Couleur de fond du bouton d'enregistrement
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), // Bordure arrondie du bouton
                      ),
                      onPressed: _isSaving ? null : _saveTrimmedVideo,
                      child: const Text(
                        'Enregistrer l’extrait sélectionné',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold), // Style du texte du bouton d'enregistrement
                      ),
                    ),
                  ),
                  const SizedBox(height: 12), // Espace entre le bouton d'enregistrement et le bouton d'annulation
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text(
                      'Annuler',
                      style: TextStyle(color: Colors.white70), // Style du texte du bouton d'annulation
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
