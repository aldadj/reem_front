import 'package:flutter/material.dart';

import '../theme/reem_theme.dart';

/// Photo en grand : on peut zoomer et déplacer.
class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({
    super.key,
    required this.imageUrl,
    this.title,
    this.onChange,
  });

  final String imageUrl;
  final String? title;

  /// Si renseigné (sur son propre profil), propose un bouton « Changer la photo ».
  final VoidCallback? onChange;

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
        title: Text(title ?? ''),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : const Center(child: CircularProgressIndicator()),
                  errorBuilder: (_, __, ___) => const Text(
                    'Impossible d’afficher la photo.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
          ),
          if (onChange != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      onChange!();
                    },
                    icon: const Icon(Icons.camera_alt_rounded, size: 18),
                    label: const Text('Changer la photo'),
                    style: ElevatedButton.styleFrom(backgroundColor: ReemColors.primary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
