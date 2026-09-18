import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/session_manager.dart';
import '../services/auth_service.dart';

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
  bool _isLoading = true;
  bool _isSending = false;
  int? _conversationId;
  List<dynamic> _messages = [];
  String? _otherUserName;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    _otherUserName = widget.otherUserName;
    _initializeConversation();
  }

  Future<void> _initializeConversation() async {
    if (!_sessionManager.isAuthenticated) return;

    if (_conversationId != null) {
      await _loadConversation();
      return;
    }

    if (widget.otherUserId != null) {
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/conversations'),
        headers: {
          'Authorization': 'Bearer ${_sessionManager.authToken}',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'other_user_id': widget.otherUserId}),
      );

      if (response.statusCode == 200) {
        final conversation = jsonDecode(response.body);
        setState(() {
          _conversationId = conversation['id'];
          _otherUserName = widget.otherUserName ?? _extractOtherUserName(conversation['participants']);
        });
        await _loadConversation();
      }
    }
  }

  String _extractOtherUserName(List<dynamic>? participants) {
    final currentUserId = _sessionManager.currentUser?['id'];
    if (participants == null) return 'Discussion';

    final other = participants.firstWhere(
      (participant) => participant['id'] != currentUserId,
      orElse: () => participants.first,
    );

    return other['name'] ?? 'Discussion';
  }

  Future<void> _loadConversation() async {
    if (_conversationId == null) return;

    setState(() => _isLoading = true);
    final response = await http.get(
      Uri.parse('${AuthService.baseUrl}/conversations/$_conversationId'),
      headers: {
        'Authorization': 'Bearer ${_sessionManager.authToken}',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final conversation = jsonDecode(response.body);
      setState(() {
        _messages = conversation['messages'] ?? [];
        _otherUserName = widget.otherUserName ?? _extractOtherUserName(conversation['participants']);
      });
    }
    setState(() => _isLoading = false);
  }

  Future<void> _sendMessage() async {
    if (_conversationId == null || _messageController.text.trim().isEmpty || _isSending) return;

    setState(() => _isSending = true);
    final body = _messageController.text.trim();

    final response = await http.post(
      Uri.parse('${AuthService.baseUrl}/conversations/$_conversationId/messages'),
      headers: {
        'Authorization': 'Bearer ${_sessionManager.authToken}',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'body': body}),
    );

    if (response.statusCode == 201) {
      final message = jsonDecode(response.body);
      setState(() {
        _messages.add(message);
        _messageController.clear();
      });
    }
    setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_otherUserName ?? 'Discussion'),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _messages.isEmpty
                    ? const Center(child: Text('Aucun message pour le moment.', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final bool fromMe = message['sender_id'] == _sessionManager.currentUser?['id'];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                              decoration: BoxDecoration(
                                color: fromMe ? Colors.blueAccent : Colors.white12,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                message['body'] ?? '',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.white10, border: Border(top: BorderSide(color: Colors.white24))),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Écrire un message...',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: _isSending ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) : const Icon(Icons.send, color: Colors.white),
                    onPressed: _isSending ? null : _sendMessage,
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
