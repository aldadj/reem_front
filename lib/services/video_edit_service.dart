import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:path_provider/path_provider.dart';

class VideoEditService {
  static const int _width = 720;
  static const int _height = 1280;
  static const int _photoDurationSeconds = 3;
  static const Set<String> _imageExtensions = {
    'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'bmp', 'gif',
  };

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

  // ---------------------------------------------------------------------------
  // FUSION DE PLUSIEURS MÉDIAS (vidéos et/ou photos, dans l'ordre donné)
  // ---------------------------------------------------------------------------

  bool _isImage(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return false;
    return _imageExtensions.contains(path.substring(dot + 1).toLowerCase());
  }

  Future<bool> _hasAudio(String videoPath) async {
    try {
      final session = await FFprobeKit.getMediaInformation(videoPath);
      final streams = session.getMediaInformation()?.getStreams() ?? const [];
      return streams.any((stream) => stream.getType() == 'audio');
    } catch (_) {
      return false;
    }
  }

  /// Assemble des vidéos et des photos en une seule vidéo 720x1280.
  ///
  /// Chaque média est d'abord converti au même format (taille, images/s,
  /// audio), puis les morceaux sont collés bout à bout sans ré-encodage.
  /// Une photo dure [_photoDurationSeconds] secondes. Les vidéos sans son
  /// reçoivent un silence pour que le résultat reste homogène.
  Future<String> mergeMedia(List<String> mediaPaths) async {
    if (mediaPaths.isEmpty) {
      throw ArgumentError('Sélectionnez au moins un média.');
    }
    for (final path in mediaPaths) {
      if (!File(path).existsSync()) {
        throw FileSystemException('Fichier introuvable.', path);
      }
    }

    final directory = await getTemporaryDirectory();
    final separator = Platform.pathSeparator;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final segments = <String>[];
    final temporaryFiles = <String>[];
    String? result;

    try {
      for (var index = 0; index < mediaPaths.length; index++) {
        final segmentPath =
            '${directory.path}${separator}reem_segment_${stamp}_$index.mp4';
        temporaryFiles.add(segmentPath);
        await _normalizeSegment(mediaPaths[index], segmentPath);
        segments.add(segmentPath);
      }

      if (segments.length == 1) {
        result = segments.first;
        temporaryFiles.remove(result);
        return result;
      }

      final listPath = '${directory.path}${separator}reem_concat_$stamp.txt';
      temporaryFiles.add(listPath);
      final buffer = StringBuffer();
      for (final segment in segments) {
        buffer.writeln("file '${segment.replaceAll("'", r"'\''")}'");
      }
      await File(listPath).writeAsString(buffer.toString(), flush: true);

      final outputPath =
          '${directory.path}${separator}reem_merged_$stamp.mp4';
      await _run([
        '-y',
        '-f',
        'concat',
        '-safe',
        '0',
        '-i',
        listPath,
        '-c',
        'copy',
        '-movflags',
        '+faststart',
        outputPath,
      ], outputPath);
      result = outputPath;
      return outputPath;
    } finally {
      for (final path in temporaryFiles) {
        try {
          final file = File(path);
          if (file.existsSync()) await file.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _normalizeSegment(String inputPath, String outputPath) async {
    final video = 'scale=$_width:$_height:force_original_aspect_ratio=decrease,'
        'pad=$_width:$_height:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30,format=yuv420p';
    const audio = 'aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo';
    const silence = 'anullsrc=r=44100:cl=stereo';
    final arguments = <String>['-y'];

    if (_isImage(inputPath)) {
      arguments.addAll([
        '-loop',
        '1',
        '-t',
        '$_photoDurationSeconds',
        '-i',
        inputPath,
        '-filter_complex',
        '[0:v]$video[v];$silence,atrim=duration=$_photoDurationSeconds[a]',
        '-map',
        '[v]',
        '-map',
        '[a]',
        '-t',
        '$_photoDurationSeconds',
      ]);
    } else {
      final hasAudio = await _hasAudio(inputPath);
      arguments.addAll([
        '-i',
        inputPath,
        '-filter_complex',
        hasAudio
            ? '[0:v:0]$video[v];[0:a:0]$audio[a]'
            : '[0:v:0]$video[v];$silence[a]',
        '-map',
        '[v]',
        '-map',
        '[a]',
      ]);
      if (!hasAudio) {
        // Le silence est infini : on borne la sortie à la durée de la vidéo.
        try {
          final duration = await getDuration(inputPath);
          arguments.addAll(['-t', (duration.inMilliseconds / 1000).toStringAsFixed(3)]);
        } catch (_) {
          arguments.add('-shortest');
        }
      }
    }

    arguments.addAll([
      '-c:v',
      'mpeg4',
      '-b:v',
      '1000k',
      '-maxrate',
      '1200k',
      '-bufsize',
      '2400k',
      '-c:a',
      'aac',
      '-b:a',
      '96k',
      '-ar',
      '44100',
      '-ac',
      '2',
      '-movflags',
      '+faststart',
      outputPath,
    ]);
    await _run(arguments, outputPath);
  }

  // ---------------------------------------------------------------------------
  // RENDU FINAL : coupe, recadrage, filtre, son
  // ---------------------------------------------------------------------------

  /// [cropFill] : false = la vidéo entière est visible (bandes noires si besoin),
  /// true = la vidéo remplit l'écran 9:16 et dépasse (recadrage).
  /// [zoom] (1 à 4) et [panX]/[panY] (-1 à 1) règlent le cadrage quand
  /// [cropFill] est vrai ; 0 = centré.
  Future<String> renderVideo({
    required String inputPath,
    required double startMilliseconds,
    required double endMilliseconds,
    required bool muteOriginal,
    required String filterName,
    String? musicPath,
    bool cropFill = false,
    double zoom = 1.0,
    double panX = 0.0,
    double panY = 0.0,
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
    final filters = <String>[];
    if (cropFill) {
      final z = zoom.clamp(1.0, 4.0).toStringAsFixed(3);
      final px = panX.clamp(-1.0, 1.0).toStringAsFixed(3);
      final py = panY.clamp(-1.0, 1.0).toStringAsFixed(3);
      filters.addAll([
        'scale=$_width:$_height:force_original_aspect_ratio=increase',
        'scale=trunc(iw*$z/2)*2:trunc(ih*$z/2)*2',
        'crop=$_width:$_height:(iw-$_width)/2*(1+($px)):(ih-$_height)/2*(1+($py))',
      ]);
    } else {
      filters.addAll([
        'scale=$_width:$_height:force_original_aspect_ratio=decrease',
        'pad=$_width:$_height:(ow-iw)/2:(oh-ih)/2',
      ]);
    }
    filters.add('setsar=1');
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