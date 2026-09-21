import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'web_publish_screen.dart';

void launchPublishScreen({
  required dynamic context,
  String? videoPath,
  Uint8List? videoBytes,
  String? fileName,
}) {
  if (videoBytes == null ||
      videoBytes.isEmpty ||
      fileName == null ||
      fileName.isEmpty) {
    return;
  }

  Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (_) => WebPublishScreen(
        videoBytes: videoBytes,
        fileName: fileName,
      ),
    ),
  );
}