import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../screens/auth_screen.dart';
import '../screens/chat_screen.dart';
import '../services/auth_service.dart';
import '../services/session_manager.dart';

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
  final ScrollController _scrollController = ScrollController();
  List<dynamic> _comments = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/videos/${widget.videoId}/comments'),
        headers: const {'Accept': 'application/json'},
      );
      if (response.statusCode == 200) {
        final comments = jsonDecode(response.body) as List<dynamic>;
        if (!mounted) return;
        setState(() {
          _comments = comments;
          _isLoading = false;
        });
        widget.onCountChanged(comments.length);
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _isSending) return;
    if (!_sessionManager.isAuthenticated) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthScreen()));
      return;
    }

    setState(() => _isSending = true);
    try {
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/videos/${widget.videoId}/comments'),
        headers: {
          'Authorization': 'Bearer ${_sessionManager.authToken}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'comment': text}),
      );
      if (response.statusCode == 201) {
        final comment = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          _comments.insert(0, comment);
          _commentController.clear();
        });
        widget.onCountChanged(_comments.length);
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

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                      '${_comments.length} commentaires',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
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
                      ? const Center(child: Text('Aucun commentaire pour le moment.', style: TextStyle(color: Colors.white60)))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _comments.length,
                          itemBuilder: (context, index) {
                            final comment = _comments[index] as Map<String, dynamic>;
                            final user = comment['user'] as Map<String, dynamic>? ?? {};
                            final int? userId = user['id'] as int?;
                            final canReply = userId != null && userId != _sessionManager.currentUser?['id'];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.white12,
                                child: Text(
                                  (user['name']?.toString().isNotEmpty ?? false)
                                      ? user['name'].toString()[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(user['name']?.toString() ?? 'Utilisateur', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(_timeAgo(comment['created_at']?.toString()), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text(comment['comment']?.toString() ?? '', style: const TextStyle(color: Colors.white)),
                              ),
                              trailing: canReply
                                  ? IconButton(
                                      tooltip: 'Répondre en message',
                                      icon: const Icon(Icons.reply, color: Colors.white54),
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChatScreen(otherUserId: userId, otherUserName: user['name']?.toString()),
                                        ),
                                      ),
                                    )
                                  : null,
                            );
                          },
                        ),
            ),
            const Divider(height: 1, color: Colors.white12),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Ajouter un commentaire...',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: Colors.white10,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _sendComment(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Envoyer',
                    onPressed: _isSending ? null : _sendComment,
                    icon: _isSending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
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
