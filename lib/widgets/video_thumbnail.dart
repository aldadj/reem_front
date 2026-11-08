import 'package:flutter/material.dart';

class VideoThumbnail extends StatelessWidget {
  const VideoThumbnail({
    super.key,
    required this.thumbnailUrl,
    required this.videoUrl,
    this.fit = BoxFit.cover,
  });

  final String thumbnailUrl;
  final String videoUrl;
  final BoxFit fit;

  String get _cloudinaryFrameUrl {
    if (!videoUrl.contains('/video/upload/')) return '';
    final withoutQuery = videoUrl.split('?').first;
    final transformed = withoutQuery.replaceFirst(
      '/video/upload/',
      '/video/upload/so_0,w_720,h_1280,c_fill,q_auto/',
    );
    return transformed.replaceFirst(
      RegExp(r'\.(mp4|mov|mkv|webm)$', caseSensitive: false),
      '.jpg',
    );
  }

  @override
  Widget build(BuildContext context) {
    final urls = <String>{
      if (thumbnailUrl.isNotEmpty) thumbnailUrl,
      if (_cloudinaryFrameUrl.isNotEmpty) _cloudinaryFrameUrl,
    }.toList();
    return _loadImage(urls, 0);
  }

  Widget _loadImage(List<String> urls, int index) {
    if (index >= urls.length) {
      return Container(
        color: const Color(0xFF171717),
        alignment: Alignment.center,
        child: const Icon(Icons.play_circle_outline, color: Colors.white54, size: 34),
      );
    }

    return Image.network(
      urls[index],
      fit: fit,
      errorBuilder: (_, __, ___) => _loadImage(urls, index + 1),
    );
  }
}
