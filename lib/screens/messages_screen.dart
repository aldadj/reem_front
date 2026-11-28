import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_settings.dart';
import '../services/inbox_service.dart';
import '../services/session_manager.dart';
import '../theme/reem_theme.dart';
import '../utils/date_labels.dart';
import '../utils/media_url.dart';
import 'chat_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'video_viewer_screen.dart';

class MessagesScreen extends StatefulWidget {
  final ValueChanged<int>? onUnreadCountChanged;

  /// Espace réservé en bas pour la barre de navigation flottante.
  final double bottomInset;

  const MessagesScreen({super.key, this.onUnreadCountChanged, this.bottomInset = 0});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final SessionManager _session = SessionManager();
  final InboxService _inbox = InboxService();

  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _onlyUnread = false;

  bool _isLoading = true;
  List<dynamic> _notifications = [];
  List<dynamic> _conversations = [];

  @override
  void initState() {
    super.initState();
    _loadData(showSpinner: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
      // On n'affiche que les types de notifications choisis dans les Paramètres
      _notifications = results[0]
          .where((n) => AppSettings.instance.allowsNotificationType('${n['type']}'))
          .toList();
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

  // Aperçu du dernier message dans la liste des discussions
  String _previewOf(Map last) {
    if (last['deleted_at'] != null) return 'Message supprimé';
    final body = '${last['body'] ?? ''}';
    return body.startsWith('REEM_VIDEO:') ? '🎬 Vidéo' : body;
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
    final target = page;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => target));
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

  /// Appui long sur une discussion (indispensable sur le web, où le glissement est peu pratique).
  Future<void> _showConversationMenu(Map<String, dynamic> conversation, String name) async {
    HapticFeedback.mediumImpact();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: sheetContext.reem.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: sheetContext.reem.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: sheetContext.reem.text, fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              ListTile(
                leading: Icon(Icons.chat_bubble_outline_rounded, color: sheetContext.reem.text),
                title: Text('Ouvrir', style: TextStyle(color: sheetContext.reem.text)),
                onTap: () => Navigator.pop(sheetContext, 'open'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: ReemColors.like),
                title: const Text('Supprimer la discussion', style: TextStyle(color: ReemColors.like)),
                onTap: () => Navigator.pop(sheetContext, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'open') {
      _openConversation(conversation);
    } else if (action == 'delete') {
      final ok = await _deleteConversation(conversation);
      if (ok && mounted) {
        setState(() => _conversations.removeWhere((c) => c['id'] == conversation['id']));
      }
    }
  }

  Future<bool?> _confirm({required String title, required String message, required String action}) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message, style: TextStyle(color: dialogContext.reem.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Annuler', style: TextStyle(color: dialogContext.reem.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
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

  String _conversationStamp(dynamic value) {
    final date = DateLabels.parse(value);
    return date == null ? '' : DateLabels.conversationStamp(date);
  }

  String _notificationStamp(dynamic value) {
    final date = DateLabels.parse(value);
    return date == null ? '' : DateLabels.notificationStamp(date);
  }

  @override
  Widget build(BuildContext context) {
    if (!_session.isAuthenticated) return _buildGuest();

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 14, 6),
            child: Row(
              children: [
                Expanded(
                  child: ShaderMask(
                    shaderCallback: (rect) => ReemColors.gradient.createShader(rect),
                    child: const Text(
                      'Messages',
                      style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                    ),
                  ),
                ),
                _roundAction(Icons.edit_square, 'Nouveau message', _showNewMessageSheet),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: 'Plus',
                  color: context.reem.surfaceHigh,
                  offset: const Offset(0, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  itemBuilder: (_) => [
                    _menuItem('read', Icons.done_all_rounded, 'Tout marquer comme lu'),
                    _menuItem('clear', Icons.delete_sweep_rounded, 'Effacer les notifications'),
                    _menuItem('refresh', Icons.refresh_rounded, 'Actualiser'),
                  ],
                  child: _roundIcon(Icons.more_horiz_rounded),
                ),
              ],
            ),
          ),
          Container(
            height: 48,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: context.reem.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.reem.border),
            ),
            child: TabBar(
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                gradient: ReemColors.gradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: ReemColors.primary.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 3)),
                ],
              ),
              labelColor: Colors.white,
              unselectedLabelColor: context.reem.textMuted,
              labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              splashBorderRadius: BorderRadius.circular(14),
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
                          decoration: BoxDecoration(color: ReemColors.like, borderRadius: BorderRadius.circular(9)),
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

  Widget _roundIcon(IconData icon) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: context.reem.surface,
        shape: BoxShape.circle,
        border: Border.all(color: context.reem.border),
      ),
      child: Icon(icon, color: context.reem.text, size: 21),
    );
  }

  Widget _roundAction(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(onTap: onTap, child: _roundIcon(icon)),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 19, color: context.reem.textSecondary),
          const SizedBox(width: 12),
          Text(label),
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
            Text(
              'Tes messages et notifications',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.reem.text, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'Connecte-toi pour voir les likes, commentaires et nouveaux abonnés, et discuter avec les autres.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.reem.textSecondary, fontSize: 14, height: 1.4),
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
      padding: EdgeInsets.only(bottom: widget.bottomInset),
      children: [
        const SizedBox(height: 70),
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [ReemColors.primary.withValues(alpha: 0.28), Colors.transparent]),
            ),
            child: Icon(icon, size: 46, color: ReemColors.primary),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.reem.text, fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.reem.textMuted, height: 1.4),
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
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.only(right: 24),
      decoration: BoxDecoration(color: ReemColors.like, borderRadius: BorderRadius.circular(20)),
      child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 26),
    );
  }

  // ---- Discussions ----

  Widget _buildConversations() {
    final q = _query.trim().toLowerCase();
    final visible = _conversations.where((c) {
      if (q.isEmpty) return true;
      final other = _otherParticipant(Map<String, dynamic>.from(c as Map));
      return (other?['name']?.toString().toLowerCase() ?? '').contains(q);
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: _conversations.isEmpty
          ? _emptyState(
              icon: Icons.forum_rounded,
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
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(bottom: widget.bottomInset + 8),
              itemCount: visible.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                    child: TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v),
                      style: TextStyle(color: context.reem.text, fontSize: 14.5),
                      decoration: InputDecoration(
                        hintText: 'Rechercher une discussion',
                        isDense: true,
                        prefixIcon: Icon(Icons.search_rounded, color: context.reem.textMuted, size: 21),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: Icon(Icons.close_rounded, color: context.reem.textMuted, size: 19),
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _query = '');
                                },
                              ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: ReemColors.primary, width: 1.2),
                        ),
                      ),
                    ),
                  );
                }
                final conversation = Map<String, dynamic>.from(visible[index - 1] as Map);
                final other = _otherParticipant(conversation);
                final messages = (conversation['messages'] as List<dynamic>?) ?? [];
                final Map? last = messages.isNotEmpty ? messages.first as Map : null;
                final mine = last != null && last['sender_id'] == _session.currentUser?['id'];
                final name = other?['name']?.toString() ?? 'Discussion';
                final unread = _asInt(conversation['unread_count']) ?? 0;
                final preview = last != null
                    ? '${mine ? 'Toi : ' : ''}${_previewOf(last)}'
                    : 'Aucun message';

                return Dismissible(
                  key: ValueKey('conv_${conversation['id']}'),
                  direction: DismissDirection.endToStart,
                  background: _deleteBackground(),
                  confirmDismiss: (_) => _deleteConversation(conversation),
                  onDismissed: (_) => setState(
                    () => _conversations.removeWhere((c) => c['id'] == conversation['id']),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    child: Material(
                      color: unread > 0 ? ReemColors.primary.withValues(alpha: 0.10) : context.reem.surface,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _openConversation(conversation),
                        onLongPress: () => _showConversationMenu(conversation, name),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: unread > 0 ? ReemColors.primary.withValues(alpha: 0.35) : context.reem.border),
                          ),
                          child: Row(
                            children: [
                              _RingAvatar(url: other?['profile_photo_path']?.toString(), name: name, radius: 25, ring: unread > 0),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w800, fontSize: 15.5),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      preview,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: unread > 0 ? context.reem.text : context.reem.textMuted,
                                        fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _conversationStamp(last?['created_at'] ?? conversation['updated_at']),
                                    style: TextStyle(
                                      color: unread > 0 ? ReemColors.primary : context.reem.textMuted,
                                      fontSize: 11.5,
                                      fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w400,
                                    ),
                                  ),
                                  if (unread > 0) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      constraints: const BoxConstraints(minWidth: 20),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(gradient: ReemColors.gradient, borderRadius: BorderRadius.circular(10)),
                                      child: Text(
                                        unread > 99 ? '99+' : '$unread',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          gradient: selected ? ReemColors.gradient : null,
          color: selected ? null : context.reem.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.transparent : context.reem.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : context.reem.textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildNotifications() {
    final source = _onlyUnread ? _notifications.where((n) => n['read_at'] == null).toList() : _notifications;
    final entries = <Object>['__filters__'];
    String? lastGroup;
    for (final item in source) {
      final date = DateLabels.parse(item['created_at']);
      final group = date == null ? 'Plus tôt' : DateLabels.notificationGroup(date);
      if (group != lastGroup) {
        entries.add(group);
        lastGroup = group;
      }
      entries.add(item);
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: _notifications.isEmpty
          ? _emptyState(
              icon: Icons.notifications_rounded,
              title: 'Aucune notification',
              subtitle: 'Les likes, commentaires et nouveaux abonnés apparaîtront ici.',
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(bottom: widget.bottomInset + 8),
              itemCount: entries.length + (source.isEmpty ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= entries.length) {
                  return Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Text('Tout est lu 🎉', style: TextStyle(color: context.reem.textMuted, fontSize: 15)),
                    ),
                  );
                }
                final entry = entries[index];
                if (entry == '__filters__') {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                    child: Row(
                      children: [
                        _filterChip('Toutes', !_onlyUnread, () => setState(() => _onlyUnread = false)),
                        const SizedBox(width: 8),
                        _filterChip(
                          _unreadCount > 0 ? 'Non lues · $_unreadCount' : 'Non lues',
                          _onlyUnread,
                          () => setState(() => _onlyUnread = true),
                        ),
                      ],
                    ),
                  );
                }
                if (entry is String) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                    child: Text(
                      entry,
                      style: TextStyle(color: context.reem.textSecondary, fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                    ),
                  );
                }
                final notification = Map<String, dynamic>.from(entry as Map);
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    child: Material(
                      color: unread ? ReemColors.primary.withValues(alpha: 0.10) : context.reem.surface,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => _openNotification(notification),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: unread ? ReemColors.primary.withValues(alpha: 0.35) : context.reem.border),
                          ),
                          child: Row(
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  _Avatar(url: actor?['profile_photo_path']?.toString(), name: name, radius: 24),
                                  Positioned(
                                    right: -4,
                                    bottom: -4,
                                    child: Container(
                                      padding: const EdgeInsets.all(4.5),
                                      decoration: BoxDecoration(
                                        color: _typeColor(type),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: context.reem.surface, width: 2),
                                      ),
                                      child: Icon(_typeIcon(type), color: Colors.white, size: 11),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      notification['message']?.toString() ?? '',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: context.reem.text,
                                        fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                                        fontSize: 14.5,
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _notificationStamp(notification['created_at']),
                                      style: TextStyle(color: context.reem.textMuted, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              if (unread) ...[
                                const SizedBox(width: 10),
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(gradient: ReemColors.gradient, shape: BoxShape.circle),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Avatar avec un anneau dégradé (violet → orange) quand il y a du nouveau.
class _RingAvatar extends StatelessWidget {
  const _RingAvatar({required this.url, required this.name, required this.radius, this.ring = false});

  final String? url;
  final String name;
  final double radius;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final avatar = _Avatar(url: url, name: name, radius: radius);
    if (!ring) return avatar;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(gradient: ReemColors.gradient, shape: BoxShape.circle),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: context.reem.surface, shape: BoxShape.circle),
        child: avatar,
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
      backgroundColor: context.reem.surfaceHigh,
      backgroundImage: photo != null ? NetworkImage(photo) : null,
      child: photo == null
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w700, fontSize: radius * 0.8),
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
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(gradient: ReemColors.gradient, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.edit_square, color: Colors.white, size: 19),
                  ),
                  const SizedBox(width: 12),
                  Text('Nouveau message', style: TextStyle(color: context.reem.text, fontSize: 19, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                style: TextStyle(color: context.reem.text),
                decoration: InputDecoration(
                  hintText: 'Rechercher un nom ou @utilisateur',
                  prefixIcon: Icon(Icons.search_rounded, color: context.reem.textMuted),
                  fillColor: context.reem.surfaceHigh,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                ),
              ),
            ),
            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person_search_rounded, size: 46, color: context.reem.border),
                              const SizedBox(height: 10),
                              Text(
                                _lastTerm.length >= 2 ? 'Personne trouvé(e)' : 'Tape au moins 2 lettres',
                                style: TextStyle(color: context.reem.textMuted),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final user = Map<String, dynamic>.from(_results[index] as Map);
                            final username = user['username']?.toString();
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Material(
                                color: context.reem.surfaceHigh,
                                borderRadius: BorderRadius.circular(18),
                                child: ListTile(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                  leading: _Avatar(
                                    url: user['profile_photo_path']?.toString(),
                                    name: user['name']?.toString() ?? '?',
                                    radius: 22,
                                  ),
                                  title: Text('${user['name']}', style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w700)),
                                  subtitle: username != null && username.isNotEmpty
                                      ? Text('@$username', style: TextStyle(color: context.reem.textMuted))
                                      : null,
                                  trailing: Icon(Icons.send_rounded, color: ReemColors.primary.withValues(alpha: 0.9), size: 20),
                                  onTap: () => widget.onUserChosen(user),
                                ),
                              ),
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
