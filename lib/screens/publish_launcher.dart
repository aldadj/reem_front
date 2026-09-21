import 'dart:typed_data';

import 'publish_launcher_native.dart'
    if (dart.library.js_interop) 'publish_launcher_web.dart';

void openPublishScreen({
  required dynamic context,
  String? videoPath,
  Uint8List? videoBytes,
  String? fileName,
}) {
  launchPublishScreen(
    context: context,
    videoPath: videoPath,
    videoBytes: videoBytes,
    fileName: fileName,
  );
}