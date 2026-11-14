import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../screens/auth_screen.dart';
import '../services/auth_service.dart';
import '../services/session_manager.dart';

/// Commentaires d'une vidéo : réponses (un niveau) et likes de commentaires.
///
/// API attendue :
///  - GET  /videos/{id}/comments        -> liste (avec `replies` imbriquées OU `parent_id`),
///                                         chaque commentaire : likes_count, liked_by_user
///  - POST /videos/{id}/comments        -> {comment, parent_id?}  (201)
///  - POST /comments/{id}/like          -> {liked, likes_count}
class VideoCommentsPanel extends StatefulWidget {
  const VideoCommentsPanel({
    super.key,
    required this.videoId,
    required this.onClose,
    required this.onCountChanged,
  });

  final int videoId;
  final VoidCallback onClose;
  final ValueChanged<int> onCountChanged;

  @override
  State<VideoCommentsPanel> createState() => _VideoCommentsPanelState();
}

class _VideoCommentsPanelState extends State<VideoCommentsPanel> {
  final SessionManager _sessionManager = SessionManager();
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _comments = []; // commentaires principaux
  final Map<int, List<Map<String, dynamic>>> _replies = {}; // parent -> réponses
  final Set<int> _expanded = {}; // commentaires dont les réponses sont ouvertes

  bool _isLoading = true;
  bool _isSending = false;

  Map<String, dynamic>? _replyTo; // commentaire auquel on répond
  int? _replyRootId; // commentaire principal auquel la réponse s'accroche

  int get _total =>
      _comments.length + _replies.values.fold<int>(0, (sum, list) => sum + list.length);

  Map<String, String> _headers({bool json = false}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if (_sessionManager.isAuthenticated)
          'Authorization': 'Bearer ${_sessionManager.authToken}',
      };

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse('$value');
  }

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // CHARGEMENT
  // ---------------------------------------------------------------------------

  Future<void> _loadComments() async {
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/videos/${widget.videoId}/comments'),
        headers: _headers(),
      );
      if (response.statusCode != 200) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final decoded = jsonDecode(response.body);
      final List raw = decoded is List
          ? decoded
          : ((decoded is Map ? (decoded['data'] ?? decoded['comments']) : null) as List? ?? []);

      // On met tout à plat (réponses imbriquées ou non) puis on regroupe par parent_id
      final all = <Map<String, dynamic>>[];
      void collect(dynamic item, {int? parentId}) {
        if (item is! Map) return;
        final map = Map<String, dynamic>.from(item);
        final nested = map.remove('replies');
        map['parent_id'] = _asInt(map['parent_id']) ?? parentId;
        all.add(map);
        if (nested is List) {
          for (final reply in nested) {
            collect(reply, parentId: _asInt(map['id']));
          }
        }
      }

      for (final item in raw) {
        collect(item);
      }

      final top = <Map<String, dynamic>>[];
      final replies = <int, List<Map<String, dynamic>>>{};
      for (final comment in all) {
        final parent = _asInt(comment['parent_id']);
        if (parent == null) {
          top.add(comment);
        } else {
          (replies[parent] ??= []).add(comment);
        }
      }
      for (final list in replies.values) {
        list.sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
      }

      if (!mounted) return;
      setState(() {
        _comments = top;
        _replies
          ..clear()
          ..addAll(replies);
        _isLoading = false;
      });
      widget.onCountChanged(_total);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  void _goToAuth() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthScreen()));
  }

  void _startReply(Map<String, dynamic> comment, int rootId) {
    final name = (comment['user'] as Map?)?['name']?.toString() ?? '';
    setState(() {
      _replyTo = comment;
      _replyRootId = rootId;
      _expanded.add(rootId);
    });
    // Réponse à une réponse : on mentionne la personne
    final isReplyToReply = _asInt(comment['id']) != rootId;
    _commentController.text = isReplyToReply && name.isNotEmpty ? '@$name ' : '';
    _commentController.selection =
        TextSelection.collapsed(offset: _commentController.text.length);
    _inputFocus.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyTo = null;
      _replyRootId = null;
    });
    _commentController.clear();
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _isSending) return;
    if (!_sessionManager.isAuthenticated) {
      _goToAuth();
      return;
    }

    final rootId = _replyRootId;
    setState(() => _isSending = true);
    try {
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/videos/${widget.videoId}/comments'),
        headers: _headers(json: true),
        body: jsonEncode({
          'comment': text,
          if (rootId != null) 'parent_id': rootId,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final created = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
        created['likes_count'] ??= 0;
        created['liked_by_user'] ??= false;
        created['parent_id'] = rootId;
        created['user'] ??= {
          'id': _sessionManager.currentUser?['id'],
          'name': _sessionManager.currentUser?['name'] ?? 'Moi',
        };

        if (!mounted) return;
        setState(() {
          if (rootId != null) {
            (_replies[rootId] ??= []).add(created);
            _expanded.add(rootId);
          } else {
            _comments.insert(0, created);
          }
          _commentController.clear();
          _replyTo = null;
          _replyRootId = null;
        });
        widget.onCountChanged(_total);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d’envoyer le commentaire.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d’envoyer le commentaire.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _toggleCommentLike(Map<String, dynamic> comment) async {
    if (!_sessionManager.isAuthenticated) {
      _goToAuth();
      return;
    }
    final id = _asInt(comment['id']);
    if (id == null) return;

    final wasLiked = comment['liked_by_user'] == true;
    final count = (comment['likes_count'] as num?)?.toInt() ?? 0;

    void apply(bool liked, int likes) {
      comment['liked_by_user'] = liked;
      comment['likes_count'] = likes < 0 ? 0 : likes;
    }

    setState(() => apply(!wasLiked, wasLiked ? count - 1 : count + 1));

    var success = false;
    try {
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/comments/$id/like'),
        headers: _headers(),
      );
      success = response.statusCode == 200;
      if (success) {
        final data = jsonDecode(response.body);
        if (mounted && data is Map) {
          setState(() {
            if (data['liked'] != null) comment['liked_by_user'] = data['liked'] == true;
            if (data['likes_count'] is num) {
              comment['likes_count'] = (data['likes_count'] as num).toInt();
            }
          });
        }
      }
    } catch (_) {}

    if (!success && mounted) {
      setState(() => apply(wasLiked, count));
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  String _timeAgo(String? value) {
    if (value == null) return '';
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return '';
    final elapsed = DateTime.now().difference(date);
    if (elapsed.inDays > 0) return 'Il y a ${elapsed.inDays} j';
    if (elapsed.inHours > 0) return 'Il y a ${elapsed.inHours} h';
    if (elapsed.inMinutes > 0) return 'Il y a ${elapsed.inMinutes} min';
    return 'À l’instant';
  }

  Widget _buildCommentTile(
    Map<String, dynamic> comment, {
    required bool isReply,
    required int rootId,
  }) {
    final user = comment['user'] as Map? ?? {};
    final name = user['name']?.toString() ?? 'Utilisateur';
    final liked = comment['liked_by_user'] == true;
    final likes = (comment['likes_count'] as num?)?.toInt() ?? 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(isReply ? 56 : 16, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: isReply ? 13 : 18,
            backgroundColor: Colors.white12,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(color: Colors.white, fontSize: isReply ? 11 : 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _timeAgo(comment['created_at']?.toString()),
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment['comment']?.toString() ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: () => _startReply(comment, rootId),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Répondre',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: liked ? 'Je n’aime plus' : 'J’aime',
                icon: Icon(
                  liked ? Icons.favorite : Icons.favorite_border,
                  color: liked ? Colors.redAccent : Colors.white54,
                  size: 20,
                ),
                onPressed: () => _toggleCommentLike(comment),
              ),
              Text(
                likes > 0 ? '$likes' : '',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRows() {
    final rows = <Widget>[];
    for (final comment in _comments) {
      final id = _asInt(comment['id']);
      if (id == null) continue;

      rows.add(_buildCommentTile(comment, isReply: false, rootId: id));

      final replies = _replies[id] ?? const <Map<String, dynamic>>[];
      if (replies.isNotEmpty) {
        final open = _expanded.contains(id);
        rows.add(
          Padding(
            padding: const EdgeInsets.only(left: 64, bottom: 4),
            child: GestureDetector(
              onTap: () => setState(() {
                open ? _expanded.remove(id) : _expanded.add(id);
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  open
                      ? 'Masquer les réponses'
                      : 'Voir ${replies.length} réponse${replies.length > 1 ? 's' : ''}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        );
        if (open) {
          for (final reply in replies) {
            rows.add(_buildCommentTile(reply, isReply: true, rootId: id));
          }
        }
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final replyName = (_replyTo?['user'] as Map?)?['name']?.toString();

    return Material(
      color: const Color(0xF0181818),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$_total commentaire${_total > 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer les commentaires',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _comments.isEmpty
                      ? const Center(
                          child: Text(
                            'Aucun commentaire pour le moment.',
                            style: TextStyle(color: Colors.white60),
                          ),
                        )
                      : ListView(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: _buildRows(),
                        ),
            ),
            const Divider(height: 1, color: Colors.white12),
            if (_replyTo != null)
              Container(
                color: Colors.white10,
                padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Réponse à ${replyName ?? 'ce commentaire'}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Annuler la réponse',
                      onPressed: _cancelReply,
                      icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      focusNode: _inputFocus,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: _replyTo != null
                            ? 'Écrire une réponse...'
                            : 'Ajouter un commentaire...',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: Colors.white10,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendComment(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Envoyer',
                    onPressed: _isSending ? null : _sendComment,
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send, color: Colors.redAccent),
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
