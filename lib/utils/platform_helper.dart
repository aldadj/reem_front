import 'package:flutter/foundation.dart';

/// Remplace `Platform.isAndroid` (dart:io) qui provoque une erreur sur le web.
bool get isAndroidPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
