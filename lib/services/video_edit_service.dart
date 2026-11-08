import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:path_provider/path_provider.dart';

class VideoEditService {
  static const int _width = 720;
  static const int _height = 1280;
  static const int _photoDurationSeconds = 3;

  Future<Duration> getDuration(String videoPath) async {
    final session = await FFprobeKit.getMediaInformation(videoPath);
    final seconds = double.tryParse(
      session.getMediaInformation()?.getDuration() ?? '',
    );
    if (seconds == null || seconds <= 0) {
      throw Exception('Durée de vidéo introuvable.');
    }
    return Duration(milliseconds: (seconds * 1000).round());
  }

  Future<String> createSlideshow(List<String> imagePaths) async {
    if (imagePaths.isEmpty) {
      throw ArgumentError('Sélectionnez au moins une photo.');
    }

    final directory = await getTemporaryDirectory();
    final outputPath =
        '${directory.path}${Platform.pathSeparator}reem_slideshow_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final arguments = <String>['-y'];

    for (final imagePath in imagePaths) {
      if (!File(imagePath).existsSync()) {
        throw FileSystemException('Photo introuvable.', imagePath);
      }
      arguments.addAll([
        '-loop',
        '1',
        '-t',
        '$_photoDurationSeconds',
        '-i',
        imagePath,
      ]);
    }

    final filters = <String>[];
    for (var index = 0; index < imagePaths.length; index++) {
      filters.add(
        '[$index:v]scale=$_width:$_height:force_original_aspect_ratio=decrease,'
        'pad=$_width:$_height:(ow-iw)/2:(oh-ih)/2,setsar=1,format=yuv420p,'
        'setpts=PTS-STARTPTS[v$index]',
      );
    }
    final inputs = List.generate(imagePaths.length, (index) => '[v$index]').join();
    filters.add('$inputs concat=n=${imagePaths.length}:v=1:a=0[outv]');

    arguments.addAll([
      '-filter_complex',
      filters.join(';'),
      '-map',
      '[outv]',
      '-an',
      '-r',
      '30',
      '-c:v',
      'mpeg4',
      '-q:v',
      '4',
      '-t',
      '${imagePaths.length * _photoDurationSeconds}',
      '-movflags',
      '+faststart',
      outputPath,
    ]);

    await _run(arguments, outputPath);
    return outputPath;
  }

  Future<String> renderVideo({
    required String inputPath,
    required double startMilliseconds,
    required double endMilliseconds,
    required bool muteOriginal,
    required String filterName,
    String? musicPath,
  }) async {
    if (!File(inputPath).existsSync()) {
      throw FileSystemException('Vidéo introuvable.', inputPath);
    }

    final durationSeconds = (endMilliseconds - startMilliseconds) / 1000;
    if (durationSeconds <= 0) {
      throw ArgumentError('La durée sélectionnée est invalide.');
    }

    if (musicPath != null && !File(musicPath).existsSync()) {
      throw FileSystemException('Fichier audio introuvable.', musicPath);
    }

    final directory = await getTemporaryDirectory();
    final outputPath =
        '${directory.path}${Platform.pathSeparator}reem_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final arguments = <String>[
      '-y',
      '-ss',
      (startMilliseconds / 1000).toStringAsFixed(3),
      '-i',
      inputPath,
    ];

    if (musicPath != null) {
      arguments.addAll(['-stream_loop', '-1', '-i', musicPath]);
    }

    arguments.addAll([
      '-t',
      durationSeconds.toStringAsFixed(3),
      '-map',
      '0:v:0',
    ]);

    if (musicPath != null) {
      arguments.addAll(['-map', '1:a:0']);
    } else if (!muteOriginal) {
      arguments.addAll(['-map', '0:a?']);
    }

    final videoFilter = switch (filterName) {
      'Gris' => 'hue=s=0',
      'Sépia' || 'Vintage' =>
        'colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131:0',
      'Froid' => 'colorbalance=rs=-0.1:bs=0.1',
      'Chaud' => 'colorbalance=rs=0.1:bs=-0.1',
      _ => null,
    };
    final filters = <String>[
      'scale=$_width:$_height:force_original_aspect_ratio=decrease',
      'pad=$_width:$_height:(ow-iw)/2:(oh-ih)/2',
      'setsar=1',
    ];
    if (videoFilter != null) filters.add(videoFilter);
    filters.add('format=yuv420p');
    arguments.addAll([
      '-vf',
      filters.join(','),
      '-c:v',
      'mpeg4',
      '-b:v',
      '1000k',
      '-maxrate',
      '1200k',
      '-bufsize',
      '2400k',
    ]);

    if (musicPath != null || !muteOriginal) {
      arguments.addAll(['-c:a', 'aac', '-b:a', '96k']);
    } else {
      arguments.add('-an');
    }

    arguments.addAll(['-movflags', '+faststart', outputPath]);
    await _run(arguments, outputPath);
    return outputPath;
  }

  Future<void> _run(List<String> arguments, String outputPath) async {
    final session = await FFmpegKit.executeWithArguments(arguments);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode) &&
        File(outputPath).existsSync() &&
        File(outputPath).lengthSync() > 0) {
      return;
    }

    final logs = await session.getOutput();
    throw Exception('Échec de préparation de la vidéo : ${logs ?? 'erreur inconnue'}');
  }
}