import 'dart:async';

import 'package:flutter/material.dart';

import '../services/inbox_service.dart';
import '../services/session_manager.dart';
import '../theme/reem_theme.dart';
import '../utils/media_url.dart';
import 'chat_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'video_viewer_screen.dart';

class MessagesScreen extends StatefulWidget {
  final ValueChanged<int>? onUnreadCountChanged;

  const MessagesScreen({super.key, this.onUnreadCountChanged});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final SessionManager _session = SessionManager();
  final InboxService _inbox = InboxService();

  bool _isLoading = true;
  List<dynamic> _notifications = [];
  List<dynamic> _conversations = [];

  @override
  void initState() {
    super.initState();
    _loadData(showSpinner: true);
  }

  // ---------------------------------------------------------------------------
  // DONNÉES
  // ---------------------------------------------------------------------------

  Future<void> _loadData({bool showSpinner = false}) async {
    if (!_session.isAuthenticated) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (showSpinner && mounted) setState(() => _isLoading = true);

    final results = await Future.wait([
      _inbox.fetchNotifications(),
      _inbox.fetchConversations(),
    ]);
    if (!mounted) return;
    setState(() {
      _notifications = results[0];
      _conversations = results[1];
      _isLoading = false;
    });
    _publishUnread();
  }

  int get _unreadCount => _notifications.where((n) => n['read_at'] == null).length;

  void _publishUnread() => widget.onUnreadCountChanged?.call(_unreadCount);

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse('$value');
  }

  // ---------------------------------------------------------------------------
  // NOTIFICATIONS
  // ---------------------------------------------------------------------------

  Future<void> _openNotification(Map<String, dynamic> notification) async {
    final id = _asInt(notification['id']);
    if (id != null && notification['read_at'] == null) {
      setState(() => notification['read_at'] = DateTime.now().toIso8601String());
      _publishUnread();
      _inbox.markRead(id);
    }

    final type = '${notification['type']}';
    final dynamic rawData = notification['data'];
    final data = rawData is Map ? rawData : const {};
    final actor = notification['actor'];

    int? videoId = _asInt(data['video_id']);
    if (videoId == null && '${notification['subject_type']}' == 'video') {
      videoId = _asInt(notification['subject_id']);
    }

    Widget? page;
    if (type == 'comment' && videoId != null) {
      // Commentaire : la vidéo, avec la section commentaires ouverte sur ce commentaire
      page = VideoViewerScreen(
        videoId: videoId,
        openComments: true,
        highlightCommentId: _asInt(data['comment_id']),
      );
    } else if ((type == 'like' || type == 'favorite') && videoId != null) {
      // Like / favori : uniquement la vidéo
      page = VideoViewerScreen(videoId: videoId);
    } else if (type == 'follow' && actor is Map) {
      final actorId = _asInt(actor['id']);
      if (actorId != null) page = ProfileScreen(userId: actorId);
    } else if (videoId != null) {
      page = VideoViewerScreen(videoId: videoId);
    } else if (actor is Map && _asInt(actor['id']) != null) {
      page = ChatScreen(otherUserId: _asInt(actor['id']), otherUserName: '${actor['name']}');
    }

    if (page == null) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page!));
    if (mounted) _loadData();
  }

  Future<bool> _deleteNotification(Map<String, dynamic> notification) async {
    final id = _asInt(notification['id']);
    if (id == null) return false;
    final ok = await _inbox.deleteNotification(id);
    if (!ok) _toast('Suppression impossible. Réessaie.');
    return ok;
  }

  Future<void> _markAllRead() async {
    if (_unreadCount == 0) return;
    final ok = await _inbox.markAllRead();
    if (!mounted) return;
    if (ok) {
      setState(() {
        for (final n in _notifications) {
          n['read_at'] ??= DateTime.now().toIso8601String();
        }
      });
      _publishUnread();
    }
  }

  Future<void> _clearNotifications() async {
    if (_notifications.isEmpty) return;
    final confirm = await _confirm(
      title: 'Tout effacer ?',
      message: 'Toutes tes notifications seront supprimées.',
      action: 'Tout effacer',
    );
    if (confirm != true) return;
    final ok = await _inbox.clearNotifications();
    if (!mounted) return;
    if (ok) {
      setState(() => _notifications = []);
      _publishUnread();
    } else {
      _toast('Suppression impossible. Réessaie.');
    }
  }

  // ---------------------------------------------------------------------------
  // DISCUSSIONS
  // ---------------------------------------------------------------------------

  Map<String, dynamic>? _otherParticipant(Map<String, dynamic> conversation) {
    final participants = (conversation['participants'] as List<dynamic>?) ?? [];
    final me = _session.currentUser?['id'];
    for (final p in participants) {
      if (p is Map && p['id'] != me) return Map<String, dynamic>.from(p);
    }
    return null;
  }

  void _openConversation(Map<String, dynamic> conversation) {
    final other = _otherParticipant(conversation);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: _asInt(conversation['id']),
          otherUserName: other?['name']?.toString() ?? 'Discussion',
        ),
      ),
    ).then((_) => _loadData());
  }

  Future<bool> _deleteConversation(Map<String, dynamic> conversation) async {
    final confirm = await _confirm(
      title: 'Supprimer la discussion ?',
      message: 'Elle disparaît de ta liste. L’autre personne la garde.',
      action: 'Supprimer',
    );
    if (confirm != true) return false;
    final id = _asInt(conversation['id']);
    if (id == null) return false;
    final ok = await _inbox.deleteConversation(id);
    if (!ok) _toast('Suppression impossible. Réessaie.');
    return ok;
  }

  Future<bool?> _confirm({required String title, required String message, required String action}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message, style: const TextStyle(color: ReemColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action, style: const TextStyle(color: ReemColors.like)),
          ),
        ],
      ),
    );
  }

  void _showNewMessageSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewMessageSheet(
        inbox: _inbox,
        onUserChosen: (user) async {
          Navigator.pop(context);
          final conversation = await _inbox.startConversation(user['id'] as int);
          if (!mounted) return;
          if (conversation == null) {
            _toast('Impossible de démarrer la discussion.');
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                conversationId: _asInt(conversation['id']),
                otherUserName: user['name']?.toString() ?? 'Discussion',
              ),
            ),
          ).then((_) => _loadData());
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  String _timeAgo(dynamic value) {
    final date = DateTime.tryParse('$value')?.toLocal();
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inDays >= 7) return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
    if (diff.inDays >= 1) return 'il y a ${diff.inDays} j';
    if (diff.inHours >= 1) return 'il y a ${diff.inHours} h';
    if (diff.inMinutes >= 1) return 'il y a ${diff.inMinutes} min';
    return 'à l’instant';
  }

  @override
  Widget build(BuildContext context) {
    if (!_session.isAuthenticated) return _buildGuest();

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Messages',
                    style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Nouveau message',
                  icon: const Icon(Icons.edit_square, color: Colors.white),
                  onPressed: _showNewMessageSheet,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                  color: ReemColors.surfaceHigh,
                  onSelected: (value) {
                    switch (value) {
                      case 'read':
                        _markAllRead();
                      case 'clear':
                        _clearNotifications();
                      case 'refresh':
                        _loadData(showSpinner: true);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'read', child: Text('Tout marquer comme lu')),
                    PopupMenuItem(value: 'clear', child: Text('Effacer les notifications')),
                    PopupMenuItem(value: 'refresh', child: Text('Actualiser')),
                  ],
                ),
              ],
            ),
          ),
          Container(
            height: 46,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: ReemColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: TabBar(
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                gradient: ReemColors.gradient,
                borderRadius: BorderRadius.circular(12),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              splashBorderRadius: BorderRadius.circular(12),
              tabs: [
                const Tab(text: 'Discussions'),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Notifications'),
                      if (_unreadCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: ReemColors.like,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            _unreadCount > 99 ? '99+' : '$_unreadCount',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    children: [
                      _buildConversations(),
                      _buildNotifications(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuest() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                gradient: ReemColors.gradient,
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 22),
            const Text(
              'Tes messages et notifications',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const Text(
              'Connecte-toi pour voir les likes, commentaires et nouveaux abonnés, et discuter avec les autres.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ReemColors.textSecondary, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
              child: const Text('Se connecter'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState({required IconData icon, required String title, required String subtitle, Widget? action}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 70),
        Icon(icon, size: 64, color: Colors.white24),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: ReemColors.textMuted, height: 1.4),
          ),
        ),
        if (action != null) ...[
          const SizedBox(height: 20),
          Center(child: action),
        ],
      ],
    );
  }

  Widget _deleteBackground() {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      color: ReemColors.like,
      child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 26),
    );
  }

  // ---- Discussions ----

  Widget _buildConversations() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: _conversations.isEmpty
          ? _emptyState(
              icon: Icons.forum_outlined,
              title: 'Aucune discussion',
              subtitle: 'Écris à quelqu’un pour commencer à discuter.',
              action: ElevatedButton.icon(
                onPressed: _showNewMessageSheet,
                icon: const Icon(Icons.edit_square, size: 18),
                label: const Text('Nouveau message'),
              ),
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _conversations.length,
              itemBuilder: (context, index) {
                final conversation = Map<String, dynamic>.from(_conversations[index] as Map);
                final other = _otherParticipant(conversation);
                final messages = (conversation['messages'] as List<dynamic>?) ?? [];
                final last = messages.isNotEmpty ? messages.first as Map : null;
                final mine = last != null && last['sender_id'] == _session.currentUser?['id'];
                final name = other?['name']?.toString() ?? 'Discussion';

                return Dismissible(
                  key: ValueKey('conv_${conversation['id']}'),
                  direction: DismissDirection.endToStart,
                  background: _deleteBackground(),
                  confirmDismiss: (_) => _deleteConversation(conversation),
                  onDismissed: (_) => setState(
                    () => _conversations.removeWhere((c) => c['id'] == conversation['id']),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                    leading: _Avatar(url: other?['profile_photo_path']?.toString(), name: name, radius: 26),
                    title: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15.5),
                    ),
                    subtitle: Text(
                      last != null ? '${mine ? 'Toi : ' : ''}${last['body'] ?? ''}' : 'Aucun message',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: ReemColors.textMuted),
                    ),
                    trailing: Text(
                      _timeAgo(last?['created_at'] ?? conversation['updated_at']),
                      style: const TextStyle(color: ReemColors.textMuted, fontSize: 12),
                    ),
                    onTap: () => _openConversation(conversation),
                  ),
                );
              },
            ),
    );
  }

  // ---- Notifications ----

  IconData _typeIcon(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite_rounded;
      case 'comment':
        return Icons.chat_bubble_rounded;
      case 'favorite':
        return Icons.bookmark_rounded;
      case 'follow':
        return Icons.person_add_alt_1_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'like':
        return ReemColors.like;
      case 'favorite':
        return ReemColors.gold;
      case 'comment':
        return ReemColors.primary;
      default:
        return ReemColors.accent;
    }
  }

  Widget _buildNotifications() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: _notifications.isEmpty
          ? _emptyState(
              icon: Icons.notifications_none_rounded,
              title: 'Aucune notification',
              subtitle: 'Les likes, commentaires et nouveaux abonnés apparaîtront ici.',
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                final notification = Map<String, dynamic>.from(_notifications[index] as Map);
                final actor = notification['actor'] is Map ? Map<String, dynamic>.from(notification['actor'] as Map) : null;
                final type = '${notification['type']}';
                final unread = notification['read_at'] == null;
                final name = actor?['name']?.toString() ?? '?';

                return Dismissible(
                  key: ValueKey('notif_${notification['id']}'),
                  direction: DismissDirection.endToStart,
                  background: _deleteBackground(),
                  confirmDismiss: (_) => _deleteNotification(notification),
                  onDismissed: (_) {
                    setState(() => _notifications.removeWhere((n) => n['id'] == notification['id']));
                    _publishUnread();
                  },
                  child: Container(
                    color: unread ? ReemColors.primary.withValues(alpha: 0.08) : Colors.transparent,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                      leading: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _Avatar(url: actor?['profile_photo_path']?.toString(), name: name, radius: 24),
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: _typeColor(type),
                                shape: BoxShape.circle,
                                border: Border.all(color: ReemColors.background, width: 2),
                              ),
                              child: Icon(_typeIcon(type), color: Colors.white, size: 11),
                            ),
                          ),
                        ],
                      ),
                      title: Text(
                        notification['message']?.toString() ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 14.5,
                          height: 1.3,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          _timeAgo(notification['created_at']),
                          style: const TextStyle(color: ReemColors.textMuted, fontSize: 12),
                        ),
                      ),
                      trailing: unread
                          ? Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(color: ReemColors.primary, shape: BoxShape.circle),
                            )
                          : null,
                      onTap: () => _openNotification(notification),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name, required this.radius});

  final String? url;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final photo = absoluteMediaUrl(url);
    return CircleAvatar(
      radius: radius,
      backgroundColor: ReemColors.surfaceHigh,
      backgroundImage: photo != null ? NetworkImage(photo) : null,
      child: photo == null
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: radius * 0.8),
            )
          : null,
    );
  }
}

/// Recherche d'une personne (nom ou @nom d'utilisateur) pour lui écrire.
class _NewMessageSheet extends StatefulWidget {
  const _NewMessageSheet({required this.inbox, required this.onUserChosen});

  final InboxService inbox;
  final ValueChanged<Map<String, dynamic>> onUserChosen;

  @override
  State<_NewMessageSheet> createState() => _NewMessageSheetState();
}

class _NewMessageSheetState extends State<_NewMessageSheet> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<dynamic> _results = [];
  bool _searching = false;
  String _lastTerm = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final term = value.trim();
    if (term.length < 2) {
      setState(() {
        _results = [];
        _searching = false;
        _lastTerm = term;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final found = await widget.inbox.searchUsers(term);
      if (!mounted) return;
      setState(() {
        _results = found;
        _searching = false;
        _lastTerm = term;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.7;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Nouveau message', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Rechercher un nom ou @utilisateur',
                  prefixIcon: Icon(Icons.search_rounded, color: ReemColors.textMuted),
                ),
              ),
            ),
            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            _lastTerm.length >= 2 ? 'Personne trouvé(e)' : 'Tape au moins 2 lettres',
                            style: const TextStyle(color: ReemColors.textMuted),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final user = Map<String, dynamic>.from(_results[index] as Map);
                            final username = user['username']?.toString();
                            return ListTile(
                              leading: _Avatar(
                                url: user['profile_photo_path']?.toString(),
                                name: user['name']?.toString() ?? '?',
                                radius: 22,
                              ),
                              title: Text('${user['name']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                              subtitle: username != null && username.isNotEmpty
                                  ? Text('@$username', style: const TextStyle(color: ReemColors.textMuted))
                                  : null,
                              onTap: () => widget.onUserChosen(user),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
