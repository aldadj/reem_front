import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'publish_screen.dart';

void launchPublishScreen({
  required dynamic context,
  String? videoPath,
  Uint8List? videoBytes,
  String? fileName,
}) {
  if (videoPath == null || videoPath.isEmpty) {
    return;
  }

  Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (_) => PublishScreen(
        videoPath: videoPath,
      ),
    ),
  );
}