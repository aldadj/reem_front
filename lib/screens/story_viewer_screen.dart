import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/story_service.dart';
import '../theme/reem_theme.dart';
import '../utils/date_labels.dart';
import '../utils/media_url.dart';

/// Lecteur de stories plein écran : une barre de progression par story,
/// toucher à droite = suivante, à gauche = précédente, maintenir = pause,
/// glisser vers le bas = fermer. Sur ses propres stories : vues et suppression.
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({super.key, required this.groups, required this.startGroup});

  /// Liste partagée avec l'écran précédent (une suppression s'y reflète)
  final List<StoryGroup> groups;
  final int startGroup;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> with SingleTickerProviderStateMixin {
  final StoryService _service = StoryService();
  late final AnimationController _progress;

  late int _groupIndex;
  int _storyIndex = 0;
  bool _paused = false;

  Player? _player;
  VideoController? _videoController;
  StreamSubscription<Duration>? _durationSub;

  StoryGroup get _group => widget.groups[_groupIndex];
  StoryItem get _story => _group.stories[_storyIndex];

  @override
  void initState() {
    super.initState();
    _groupIndex = widget.startGroup.clamp(0, widget.groups.length - 1);
    _storyIndex = _firstUnseen(_group);
    _progress = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _next();
      });
    _startStory();
  }

  @override
  void dispose() {
    _progress.dispose();
    _disposePlayer();
    super.dispose();
  }

  int _firstUnseen(StoryGroup group) {
    final index = group.stories.indexWhere((story) => !story.viewed);
    return index < 0 ? 0 : index;
  }

  void _disposePlayer() {
    _durationSub?.cancel();
    _durationSub = null;
    _player?.dispose();
    _player = null;
    _videoController = null;
  }

  // ---------------------------------------------------------------------------
  // LECTURE
  // ---------------------------------------------------------------------------

  Future<void> _startStory() async {
    _disposePlayer();
    _progress.stop();
    _progress.value = 0;

    final story = _story;
    if (!_group.isMe && !story.viewed) {
      story.viewed = true;
      _service.markViewed(story.id);
    }
    if (mounted) setState(() {});

    if (story.isVideo) {
      final player = Player();
      _player = player;
      _videoController = VideoController(player);
      if (mounted) setState(() {});

      var started = false;
      void begin(Duration duration) {
        if (started || _player != player) return;
        started = true;
        _progress.duration = duration;
        if (!_paused) _progress.forward(from: 0);
      }

      _durationSub = player.stream.duration.listen((duration) {
        if (duration > Duration.zero) begin(duration);
      });
      await player.open(Media(story.mediaUrl), play: !_paused);

      // Si la durée n'est jamais annoncée, on avance quand même
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && !started) begin(const Duration(seconds: 15));
      });
    } else {
      _progress.duration = const Duration(seconds: 5);
      if (!_paused) _progress.forward(from: 0);
    }
  }

  void _next() {
    if (_storyIndex < _group.stories.length - 1) {
      setState(() => _storyIndex++);
      _startStory();
    } else if (_groupIndex < widget.groups.length - 1) {
      setState(() {
        _groupIndex++;
        _storyIndex = _firstUnseen(_group);
      });
      _startStory();
    } else {
      _close();
    }
  }

  void _previous() {
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
    } else if (_groupIndex > 0) {
      setState(() {
        _groupIndex--;
        _storyIndex = _group.stories.length - 1;
      });
    }
    _startStory();
  }

  void _pause() {
    _paused = true;
    _progress.stop();
    _player?.pause();
  }

  void _resume() {
    _paused = false;
    if (_progress.duration != null) _progress.forward();
    _player?.play();
  }

  void _close() {
    if (mounted) Navigator.of(context).pop(true);
  }

  // ---------------------------------------------------------------------------
  // ACTIONS SUR SES STORIES
  // ---------------------------------------------------------------------------

  Future<void> _deleteCurrent() async {
    _pause();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette story ?'),
        content: const Text('Elle disparaîtra pour tout le monde.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Annuler', style: TextStyle(color: context.reem.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: ReemColors.like)),
          ),
        ],
      ),
    );
    if (confirm != true) {
      if (mounted) _resume();
      return;
    }

    final ok = await _service.delete(_story.id);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suppression impossible. Réessaie.')),
      );
      _resume();
      return;
    }

    final group = _group;
    group.stories.removeAt(_storyIndex);
    if (group.stories.isEmpty) {
      widget.groups.removeAt(_groupIndex);
      if (widget.groups.isEmpty || _groupIndex >= widget.groups.length) {
        _close();
        return;
      }
      _storyIndex = 0;
    } else if (_storyIndex >= group.stories.length) {
      _storyIndex = group.stories.length - 1;
    }
    setState(() {});
    _startStory();
  }

  Future<void> _showViewers() async {
    _pause();
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _service.viewers(_story.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
          }
          final viewers = snapshot.data ?? [];
          if (viewers.isEmpty) {
            return SizedBox(
              height: 160,
              child: Center(
                child: Text('Personne n’a encore vu cette story.', style: TextStyle(color: context.reem.textMuted)),
              ),
            );
          }
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: viewers.length,
              itemBuilder: (context, index) {
                final user = Map<String, dynamic>.from(viewers[index]['user'] as Map);
                final photo = absoluteMediaUrl(user['profile_photo_path']?.toString());
                final name = '${user['name'] ?? ''}';
                final date = DateLabels.parse(viewers[index]['viewed_at']);
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: context.reem.surfaceHigh,
                    backgroundImage: photo != null ? NetworkImage(photo) : null,
                    child: photo == null ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?') : null,
                  ),
                  title: Text(name, style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w600)),
                  subtitle: date == null
                      ? null
                      : Text(DateLabels.notificationStamp(date), style: TextStyle(color: context.reem.textMuted)),
                );
              },
            ),
          );
        },
      ),
    );
    if (mounted) _resume();
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  String _ago(DateTime? date) {
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'à l’instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    return 'il y a ${diff.inHours} h';
  }

  String _remaining(DateTime? expires) {
    if (expires == null) return '';
    final left = expires.difference(DateTime.now());
    if (left.inMinutes <= 0) return 'Expire bientôt';
    if (left.inHours >= 1) return 'Disparaît dans ${left.inHours} h';
    return 'Disparaît dans ${left.inMinutes} min';
  }

  Widget _media() {
    final story = _story;
    if (story.isVideo) {
      final controller = _videoController;
      if (controller == null) return const Center(child: CircularProgressIndicator());
      return Video(controller: controller, controls: NoVideoControls, fit: BoxFit.contain);
    }
    return Image.network(
      story.mediaUrl,
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, loading) =>
          loading == null ? child : const Center(child: CircularProgressIndicator()),
      errorBuilder: (_, __, ___) => const Center(
        child: Text('Impossible d’afficher la story.', style: TextStyle(color: Colors.white70)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = _group;
    final story = _story;
    final photo = absoluteMediaUrl(group.photo);
    const shadow = [Shadow(color: Color(0x99000000), blurRadius: 6)];

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 700) _close();
        },
        onLongPressStart: (_) => _pause(),
        onLongPressEnd: (_) => _resume(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _media(),

            // Zones de toucher : gauche = précédente, droite = suivante
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _previous),
                ),
                Expanded(
                  flex: 2,
                  child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _next),
                ),
              ],
            ),

            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: AnimatedBuilder(
                      animation: _progress,
                      builder: (context, _) => Row(
                        children: [
                          for (var i = 0; i < group.stories.length; i++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: i < _storyIndex ? 1 : (i == _storyIndex ? _progress.value : 0),
                                    minHeight: 2.5,
                                    backgroundColor: Colors.white30,
                                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.white24,
                          backgroundImage: photo != null ? NetworkImage(photo) : null,
                          child: photo == null
                              ? Text(group.name.isNotEmpty ? group.name[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Colors.white))
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.isMe ? 'Ta story' : group.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, shadows: shadow),
                              ),
                              Text(
                                group.isMe ? _remaining(story.expiresAt) : _ago(story.createdAt),
                                style: const TextStyle(color: Colors.white70, fontSize: 12, shadows: shadow),
                              ),
                            ],
                          ),
                        ),
                        if (group.isMe)
                          IconButton(
                            tooltip: 'Supprimer la story',
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white, shadows: shadow),
                            onPressed: _deleteCurrent,
                          ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white, shadows: shadow),
                          onPressed: _close,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if ((story.caption ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
                      child: Text(
                        story.caption!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600, height: 1.3, shadows: shadow),
                      ),
                    ),
                  if (group.isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextButton.icon(
                        onPressed: _showViewers,
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        icon: const Icon(Icons.visibility_outlined, size: 20),
                        label: Text('${story.viewsCount ?? 0} vue${(story.viewsCount ?? 0) > 1 ? 's' : ''}'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
