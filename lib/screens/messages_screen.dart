import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/session_manager.dart';
import '../services/auth_service.dart';
import 'chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  final ValueChanged<int>? onUnreadCountChanged;

  const MessagesScreen({super.key, this.onUnreadCountChanged});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final SessionManager _sessionManager = SessionManager();
  bool _isLoading = true;
  List<dynamic> _notifications = [];
  List<dynamic> _conversations = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await Future.wait([_fetchNotifications(), _fetchConversations()]);
    setState(() => _isLoading = false);
  }

  Future<void> _fetchNotifications() async {
    if (!_sessionManager.isAuthenticated) return;
    final response = await http.get(
      Uri.parse('${AuthService.baseUrl}/notifications'),
      headers: {
        'Authorization': 'Bearer ${_sessionManager.authToken}',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      setState(() {
        _notifications = jsonDecode(response.body);
      });
      widget.onUnreadCountChanged?.call(_unreadNotificationCount());
    }
  }

  int _unreadNotificationCount() {
    return _notifications.where((notification) => notification['read_at'] == null).length;
  }

  Future<void> _fetchConversations() async {
    if (!_sessionManager.isAuthenticated) return;
    final response = await http.get(
      Uri.parse('${AuthService.baseUrl}/conversations'),
      headers: {
        'Authorization': 'Bearer ${_sessionManager.authToken}',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      setState(() {
        _conversations = jsonDecode(response.body);
      });
    }
  }

  Future<void> _markNotificationRead(int id) async {
    await http.post(
      Uri.parse('${AuthService.baseUrl}/notifications/$id/read'),
      headers: {
        'Authorization': 'Bearer ${_sessionManager.authToken}',
        'Accept': 'application/json',
      },
    );
    await _fetchNotifications();
  }

  Future<void> _startConversation(int otherUserId, String otherUserName) async {
    final response = await http.post(
      Uri.parse('${AuthService.baseUrl}/conversations'),
      headers: {
        'Authorization': 'Bearer ${_sessionManager.authToken}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'other_user_id': otherUserId}),
    );
    if (response.statusCode == 200) {
      final conversation = jsonDecode(response.body);
      _openChat(conversation['id'], otherUserName);
    }
  }

  void _openChat(int conversationId, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          conversationId: conversationId,
          otherUserName: title,
        ),
      ),
    ).then((_) => _loadData());
  }

  void _openChatWithUser(int userId, String userName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          otherUserId: userId,
          otherUserName: userName,
        ),
      ),
    ).then((_) => _loadData());
  }

  @override
  Widget build(BuildContext context) {
    if (!_sessionManager.isAuthenticated) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey),
              const SizedBox(height: 24),
              const Text(
                'Connectez-vous pour voir vos notifications et messages',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Vous recevrez ici les likes, commentaires et favoris sur vos vidéos, et vous pourrez discuter avec d’autres utilisateurs.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Messages & Notifications'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.add_comment),
            onPressed: _showStartConversationDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Notifications', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (_notifications.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text('Aucune notification pour le moment.', style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ..._notifications.map((notification) {
                      final actor = notification['actor'];
                      final isRead = notification['read_at'] != null;
                      return Card(
                        color: isRead ? Colors.white10 : Colors.white12,
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(notification['message'] ?? '', style: const TextStyle(color: Colors.white)),
                          subtitle: Text(
                            actor != null ? '${actor['name']} · ${notification['type']}' : notification['type'] ?? '',
                            style: const TextStyle(color: Colors.grey),
                          ),
                          trailing: Icon(isRead ? Icons.check : Icons.circle, color: isRead ? Colors.green : Colors.redAccent, size: 14),
                          onTap: () async {
                            await _markNotificationRead(notification['id']);
                            if (actor != null) {
                              _openChatWithUser(actor['id'], actor['name']);
                            }
                          },
                        ),
                      );
                    }),
                  const SizedBox(height: 24),
                  const Text('Discussions', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (_conversations.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text('Aucune discussion active. Répondez à un commentaire ou ouvrez une nouvelle conversation.', style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ..._conversations.map((conversation) {
                      final participants = (conversation['participants'] as List<dynamic>?) ?? [];
                      final currentUserId = _sessionManager.currentUser?['id'];
                      final otherUser = participants.firstWhere(
                        (participant) => participant['id'] != currentUserId,
                        orElse: () => participants.isNotEmpty ? participants.first : null,
                      );
                      final latestMessage = (conversation['messages'] as List<dynamic>?)?.firstWhere(
                        (message) => true,
                        orElse: () => null,
                      );

                      return Card(
                        color: Colors.white10,
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(otherUser != null ? otherUser['name'] : 'Conversation', style: const TextStyle(color: Colors.white)),
                          subtitle: Text(
                            latestMessage != null ? (latestMessage['body'] ?? '') : 'Aucun message',
                            style: const TextStyle(color: Colors.grey),
                          ),
                          onTap: () {
                            _openChat(conversation['id'], otherUser != null ? otherUser['name'] : 'Discussion');
                          },
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }

  void _showStartConversationDialog() {
    final TextEditingController userIdController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Nouveau message', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: userIdController,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'ID utilisateur',
            hintStyle: TextStyle(color: Colors.white38),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              final idText = userIdController.text.trim();
              if (idText.isNotEmpty) {
                final userId = int.tryParse(idText);
                if (userId != null) {
                  Navigator.of(context).pop();
                  _startConversation(userId, 'Discussion');
                }
              }
            },
            child: const Text('Démarrer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
