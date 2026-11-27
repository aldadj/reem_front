import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/video.dart' as app_models;
import '../services/auth_service.dart';
import '../services/inbox_service.dart';
import '../services/session_manager.dart';
import '../theme/reem_theme.dart';
import '../utils/date_labels.dart';
import '../utils/media_url.dart';
import '../widgets/video_player_item.dart';
import '../widgets/video_thumbnail.dart';

/// Conversation façon WhatsApp : bulles, heure sur chaque message,
/// séparateurs « Aujourd'hui », « Hier », jour de la semaine…
class ChatScreen extends StatefulWidget {
  final int? conversationId;
  final int? otherUserId;
  final String? otherUserName;

  const ChatScreen({
    Key? key,
    this.conversationId,
    this.otherUserId,
    this.otherUserName,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final SessionManager _sessionManager = SessionManager();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final InboxService _inbox = InboxService();
  Timer? _refreshTimer;
  Map<String, dynamic>? _replyTo;

  bool _isLoading = true;
  bool _isSending = false;
  int? _conversationId;
  List<dynamic> _messages = [];
  String? _otherUserName;
  String? _otherUserPhoto;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${_sessionManager.authToken}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    _otherUserName = widget.otherUserName;
    _messageController.addListener(() => setState(() {}));
    _initializeConversation();
    // Les nouveaux messages arrivent sans quitter l'écran
    _refreshTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_isSending) _loadConversation(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _messageController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _initializeConversation() async {
    if (!_sessionManager.isAuthenticated) {
      setState(() => _isLoading = false);
      return;
    }

    if (_conversationId != null) {
      await _loadConversation();
      return;
    }

    if (widget.otherUserId != null) {
      try {
        final response = await http.post(
          Uri.parse('${AuthService.baseUrl}/conversations'),
          headers: _headers,
          body: jsonEncode({'other_user_id': widget.otherUserId}),
        );

        if (response.statusCode == 200) {
          final conversation = jsonDecode(response.body);
          setState(() {
            _conversationId = conversation['id'];
            _applyParticipants(conversation['participants']);
          });
          await _loadConversation();
          return;
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _applyParticipants(List<dynamic>? participants) {
    if (participants == null || participants.isEmpty) return;
    final currentUserId = _sessionManager.currentUser?['id'];
    final other = participants.firstWhere(
      (participant) => participant['id'] != currentUserId,
      orElse: () => participants.first,
    );
    _otherUserName = widget.otherUserName ?? other['name']?.toString() ?? 'Discussion';
    _otherUserPhoto = other['profile_photo_path']?.toString();
  }

  Future<void> _loadConversation({bool silent = false}) async {
    if (_conversationId == null) return;

    if (!silent) setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/conversations/$_conversationId'),
        headers: _headers,
      );

      if (response.statusCode == 200 && mounted) {
        final conversation = jsonDecode(response.body);
        final incoming = List<dynamic>.from(conversation['messages'] ?? []);
        setState(() {
          _messages = incoming;
          _applyParticipants(conversation['participants']);
        });
      }
    } catch (_) {}
    if (mounted && !silent) setState(() => _isLoading = false);
  }

  Future<void> _sendMessage() async {
    final body = _messageController.text.trim();
    if (_conversationId == null || body.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    try {
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/conversations/$_conversationId/messages'),
        headers: _headers,
        body: jsonEncode({
          'body': body,
          if (_replyTo != null) 'reply_to_id': _replyTo!['id'],
        }),
      );

      if (response.statusCode == 201 && mounted) {
        final message = jsonDecode(response.body);
        setState(() {
          _messages.add(message);
          _messageController.clear();
          _replyTo = null;
        });
        if (_scroll.hasClients) _scroll.jumpTo(0); // la liste est inversée : 0 = dernier message
      } else if (mounted) {
        _toast('Message non envoyé. Réessaie.');
      }
    } catch (_) {
      _toast('Message non envoyé. Vérifie ta connexion.');
    }
    if (mounted) setState(() => _isSending = false);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------------
  // ACTIONS SUR UN MESSAGE (appui long)
  // ---------------------------------------------------------------------------

  static const List<String> _quickEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  int? get _myId {
    final id = _sessionManager.currentUser?['id'];
    return id is int ? id : int.tryParse('$id');
  }

  bool _isDeleted(Map<String, dynamic> message) => message['deleted_at'] != null;

  /// Texte court d'un message (pour l'aperçu de réponse).
  String _previewOf(Map<String, dynamic>? message) {
    if (message == null) return '';
    if (message['deleted_at'] != null) return 'Message supprimé';
    final body = '${message['body'] ?? ''}';
    if (body.startsWith('REEM_VIDEO:')) return '🎬 Vidéo partagée';
    return body;
  }

  Future<void> _showMessageActions(Map<String, dynamic> message) async {
    if (_isDeleted(message)) return;
    HapticFeedback.mediumImpact();
    final fromMe = message['sender_id'] == _myId;
    final body = '${message['body'] ?? ''}';
    final isVideo = body.startsWith('REEM_VIDEO:');

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        Widget tile(IconData icon, String label, String value, {Color? color}) {
          return ListTile(
            leading: Icon(icon, color: color ?? context.reem.text),
            title: Text(label, style: TextStyle(color: color ?? context.reem.text, fontWeight: FontWeight.w600)),
            onTap: () => Navigator.pop(sheetContext, value),
          );
        }

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: context.reem.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: context.reem.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final emoji in _quickEmojis)
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Navigator.pop(sheetContext, 'react:$emoji'),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(emoji, style: const TextStyle(fontSize: 28)),
                          ),
                        ),
                    ],
                  ),
                ),
                Divider(height: 1, color: context.reem.border),
                tile(Icons.reply_rounded, 'Répondre', 'reply'),
                if (!isVideo) tile(Icons.copy_rounded, 'Copier', 'copy'),
                if (fromMe) tile(Icons.delete_outline_rounded, 'Supprimer pour tout le monde', 'delete', color: ReemColors.like),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    if (action == 'reply') {
      setState(() => _replyTo = message);
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: body));
      _toast('Message copié.');
    } else if (action == 'delete') {
      await _deleteMessage(message);
    } else if (action.startsWith('react:')) {
      await _react(message, action.substring(6));
    }
  }

  Future<void> _deleteMessage(Map<String, dynamic> message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer ce message ?'),
        content: const Text('Il sera supprimé pour tout le monde dans cette discussion.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer', style: TextStyle(color: ReemColors.like)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final id = message['id'];
    final index = _messages.indexWhere((m) => m['id'] == id);
    if (index < 0) return;
    final backup = _messages[index];

    // Affichage immédiat, retour en arrière si le serveur refuse
    setState(() {
      _messages[index] = {
        ...Map<String, dynamic>.from(backup as Map),
        'body': '',
        'deleted_at': DateTime.now().toIso8601String(),
        'reactions': <dynamic>[],
      };
      if (_replyTo != null && _replyTo!['id'] == id) _replyTo = null;
    });

    final done = await _inbox.deleteMessage(id as int);
    if (!done && mounted) {
      final i = _messages.indexWhere((m) => m['id'] == id);
      if (i >= 0) setState(() => _messages[i] = backup);
      _toast('Suppression impossible. Réessaie.');
    }
  }

  Future<void> _react(Map<String, dynamic> message, String emoji) async {
    final id = message['id'] as int;
    final result = await _inbox.reactToMessage(id, emoji);
    if (!mounted) return;
    if (result == null) {
      _toast('Réaction non envoyée.');
      return;
    }
    final index = _messages.indexWhere((m) => m['id'] == id);
    if (index >= 0) {
      setState(() {
        _messages[index] = {...Map<String, dynamic>.from(_messages[index] as Map), 'reactions': result};
      });
    }
  }

  Future<void> _confirmDeleteConversation() async {
    final id = _conversationId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer la discussion ?'),
        content: const Text('Elle disparaît de ta liste. L\'autre personne la conserve de son côté.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Supprimer', style: TextStyle(color: ReemColors.like)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final done = await _inbox.deleteConversation(id);
    if (!mounted) return;
    if (done) {
      Navigator.pop(context, true); // la liste se rafraîchit à son retour
    } else {
      _toast('Suppression impossible. Réessaie.');
    }
  }

  Widget _reactionsRow(Map<String, dynamic> message, bool fromMe) {
    final reactions = (message['reactions'] as List?) ?? const [];
    if (reactions.isEmpty) return const SizedBox.shrink();

    final counts = <String, int>{};
    for (final r in reactions) {
      final emoji = '${r['emoji']}';
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    final mine = reactions.where((r) => r['user_id'] == _myId).map((r) => '${r['emoji']}').toSet();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        children: [
          for (final entry in counts.entries)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: context.reem.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: mine.contains(entry.key) ? ReemColors.primary : context.reem.border),
              ),
              child: Text(
                entry.value > 1 ? '${entry.key} ${entry.value}' : entry.key,
                style: TextStyle(color: context.reem.text, fontSize: 12.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _replyPreviewInBubble(Map<String, dynamic> message, bool fromMe) {
    final reply = message['reply_to'];
    if (reply is! Map) return const SizedBox.shrink();
    final r = Map<String, dynamic>.from(reply);
    final author = (r['sender'] is Map ? r['sender']['name'] : null)?.toString() ?? 'Message';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: fromMe ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: fromMe ? Colors.white : ReemColors.primary, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: fromMe ? Colors.white : ReemColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            _previewOf(r),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fromMe ? Colors.white70 : context.reem.textSecondary, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _replyComposerBar() {
    final reply = _replyTo;
    if (reply == null) return const SizedBox.shrink();
    final mine = reply['sender_id'] == _myId;
    final author = mine ? 'Toi' : (_otherUserName ?? 'Message');
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: context.reem.surface,
        border: Border(top: BorderSide(color: context.reem.border)),
      ),
      child: Row(
        children: [
          Container(width: 3, height: 34, color: ReemColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Réponse à $author',
                    style: const TextStyle(color: ReemColors.primary, fontSize: 12.5, fontWeight: FontWeight.w700)),
                Text(_previewOf(reply),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.reem.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: context.reem.textMuted),
            onPressed: () => setState(() => _replyTo = null),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CONTENU DES MESSAGES
  // ---------------------------------------------------------------------------

  Widget _buildMessageContent(String body, bool fromMe) {
    final textColor = fromMe ? Colors.white : context.reem.text;
    const marker = 'REEM_VIDEO:';

    if (!body.startsWith(marker)) {
      return Text(body, style: TextStyle(color: textColor, fontSize: 15, height: 1.3));
    }

    try {
      final shared = jsonDecode(body.substring(marker.length)) as Map<String, dynamic>;
      final videoUrl = shared['video_url']?.toString() ?? '';
      final video = app_models.Video(
        id: shared['id'] as int,
        videoUrl: videoUrl,
        title: shared['title']?.toString() ?? 'Vidéo partagée',
        description: shared['description']?.toString(),
        username: shared['username']?.toString() ?? 'Utilisateur',
        authorId: shared['author_id'] as int? ?? 0,
        likesCount: shared['likes_count'] as int? ?? 0,
        commentsCount: shared['comments_count'] as int? ?? 0,
        isLiked: false,
        isFavorited: false,
      );

      return InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              body: VideoPlayerItem(video: video, feedVisible: ValueNotifier<bool>(true)),
            ),
          ),
        ),
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 190,
                  child: VideoThumbnail(thumbnailUrl: '', videoUrl: videoUrl),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                video.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
              ),
              Text(
                'Vidéo de @${video.username} · Appuyer pour regarder',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 12),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      return Text('Vidéo partagée', style: TextStyle(color: textColor));
    }
  }

  // Liste affichée : messages et séparateurs de jour (du plus ancien au plus récent)
  List<Object> _timeline() {
    final entries = <Object>[];
    String? lastDay;
    for (final message in _messages) {
      final date = DateLabels.parse(message['created_at']);
      if (date != null) {
        final day = '${date.year}-${date.month}-${date.day}';
        if (day != lastDay) {
          entries.add(DateLabels.dayLabel(date));
          lastDay = day;
        }
      }
      entries.add(message);
    }
    return entries;
  }

  Widget _daySeparator(String label) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: context.reem.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: TextStyle(color: context.reem.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _bubble(Map<String, dynamic> message) {
    final fromMe = message['sender_id'] == _myId;
    final date = DateLabels.parse(message['created_at']);
    final deleted = _isDeleted(message);
    final body = '${message['body'] ?? ''}';

    final Widget content = deleted
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block_rounded, size: 15, color: fromMe ? Colors.white70 : context.reem.textMuted),
              const SizedBox(width: 6),
              Text(
                'Message supprimé',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 14,
                  color: fromMe ? Colors.white70 : context.reem.textMuted,
                ),
              ),
            ],
          )
        : _buildMessageContent(body, fromMe);

    return Align(
      alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: deleted ? null : () => _showMessageActions(message),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 6),
          decoration: BoxDecoration(
            color: fromMe ? ReemColors.primary : context.reem.surface,
            border: fromMe ? null : Border.all(color: context.reem.border),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(fromMe ? 16 : 4),
              bottomRight: Radius.circular(fromMe ? 4 : 16),
            ),
          ),
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!deleted) _replyPreviewInBubble(message, fromMe),
                content,
                if (!deleted) _reactionsRow(message, fromMe),
                if (date != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        DateLabels.clock(date),
                        style: TextStyle(
                          color: fromMe ? Colors.white70 : context.reem.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = absoluteMediaUrl(_otherUserPhoto);
    final name = _otherUserName ?? 'Discussion';
    final timeline = _timeline().reversed.toList();

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: context.reem.surfaceHigh,
              backgroundImage: photo != null ? NetworkImage(photo) : null,
              child: photo == null
                  ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w700))
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'delete') _confirmDeleteConversation();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded, color: ReemColors.like),
                    SizedBox(width: 10),
                    Text('Supprimer la discussion'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'Aucun message pour le moment.\nDis bonjour !',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.reem.textMuted, height: 1.4),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        reverse: true, // on démarre en bas, sur le dernier message
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                        itemCount: timeline.length,
                        itemBuilder: (context, index) {
                          final entry = timeline[index];
                          if (entry is String) return _daySeparator(entry);
                          return _bubble(Map<String, dynamic>.from(entry as Map));
                        },
                      ),
          ),
          _replyComposerBar(),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                color: context.reem.background,
                border: Border(top: BorderSide(color: context.reem.border)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(color: context.reem.text),
                      decoration: InputDecoration(
                        hintText: 'Écrire un message…',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _messageController.text.trim().isEmpty || _isSending ? null : _sendMessage,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: _messageController.text.trim().isEmpty ? null : ReemColors.gradient,
                        color: _messageController.text.trim().isEmpty ? context.reem.surfaceHigh : null,
                        shape: BoxShape.circle,
                      ),
                      child: _isSending
                          ? const Padding(
                              padding: EdgeInsets.all(13),
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(
                              Icons.send_rounded,
                              color: _messageController.text.trim().isEmpty ? context.reem.textMuted : Colors.white,
                              size: 22,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
