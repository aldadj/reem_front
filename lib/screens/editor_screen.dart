import 'dart:io';

import 'package:flutter/material.dart';

import 'publish_screen.dart';

class EditorScreen extends StatelessWidget {
  const EditorScreen({super.key, required this.videoFile});

  final File videoFile;

  @override
  Widget build(BuildContext context) {
    return PublishScreen(videoPath: videoFile.path);
  }
}
