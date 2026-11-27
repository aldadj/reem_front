import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/search_service.dart';
import '../services/session_manager.dart';
import '../services/user_service.dart';
import '../services/video_interaction_store.dart';
import '../theme/reem_theme.dart';
import '../utils/media_url.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'video_viewer_screen.dart';
import '../widgets/video_thumbnail.dart';

/// Recherche façon TikTok : Top, Utilisateurs, Vidéos, Photos, Live, Sons, Hashtags.
/// Les onglets sans données réelles pour le moment (Photos, Live, Sons) le disent clairement.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  static const _tabs = ['Top', 'Utilisateurs', 'Vidéos', 'Photos', 'Live', 'Sons', 'Hashtags'];
  static const _types = ['top', 'users', 'videos', null, null, null, 'hashtags'];

  final SearchService _search = SearchService();
  final SessionManager _session = SessionManager();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  late final TabController _tabController;
  Timer? _debounce;

  String _query = '';
  final Map<String, SearchResults?> _cache = {}; // type -> résultats pour _query
  final Set<String> _loading = {};
  List<Map<String, dynamic>> _trending = [];
  final Map<int, bool> _following = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _loadCurrentTab();
    });
    _search.trendingHashtags().then((tags) {
      if (mounted) setState(() => _trending = tags);
    });

    final initial = widget.initialQuery;
    if (initial != null && initial.trim().isNotEmpty) {
      _controller.text = initial;
      _submit(initial);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // RECHERCHE
  // ---------------------------------------------------------------------------

  void _onChanged(String value) {
    _debounce?.cancel();
    final term = value.trim();
    if (term.isEmpty) {
      setState(() {
        _query = '';
        _cache.clear();
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _submit(term, remember: false));
  }

  void _submit(String value, {bool remember = true}) {
    final term = value.trim();
    if (term.isEmpty) return;

    if (remember) {
      AppSettings.instance.update(() {
        final recents = AppSettings.instance.recentSearches;
        recents.removeWhere((item) => item.toLowerCase() == term.toLowerCase());
        recents.insert(0, term);
        if (recents.length > 10) recents.removeLast();
      });
      _focus.unfocus();
    }

    setState(() {
      _query = term;
      _cache.clear();
    });
    _loadCurrentTab();
  }

  void _useSuggestion(String text) {
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    _submit(text);
  }

  Future<void> _loadCurrentTab() async {
    final type = _types[_tabController.index];
    if (type == null || _query.isEmpty || _cache.containsKey(type) || _loading.contains(type)) return;

    final term = _query;
    setState(() => _loading.add(type));
    final results = await _search.search(term, type);
    if (!mounted || term != _query) return;
    setState(() {
      _loading.remove(type);
      _cache[type] = results ?? const SearchResults();
    });
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  void _openVideo(Map<String, dynamic> video) {
    final id = int.tryParse('${video['id']}');
    if (id == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => VideoViewerScreen(videoId: id)));
  }

  void _openProfile(Map<String, dynamic> user) {
    final id = int.tryParse('${user['id']}');
    if (id == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: id)));
  }

  bool _isFollowing(Map<String, dynamic> user) {
    final id = int.tryParse('${user['id']}') ?? -1;
    return _following[id] ?? FollowCache.stateOf(id) ?? user['is_following'] == true;
  }

  Future<void> _toggleFollow(Map<String, dynamic> user) async {
    if (!_session.isAuthenticated) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }
    final id = int.tryParse('${user['id']}');
    if (id == null) return;

    final result = await UserService().toggleFollow(id, _session.authToken!);
    if (!mounted || result == null) return;
    final following = result['following'] == true;
    FollowCache.set(id, following);
    setState(() => _following[id] = following);
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      autofocus: widget.initialQuery == null,
                      textInputAction: TextInputAction.search,
                      onChanged: _onChanged,
                      onSubmitted: _submit,
                      style: TextStyle(color: context.reem.text),
                      decoration: InputDecoration(
                        hintText: 'Rechercher',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _controller.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  _controller.clear();
                                  _onChanged('');
                                  setState(() {});
                                },
                              ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: () => _submit(_controller.text),
                    child: const Text('Rechercher'),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: context.reem.text,
              labelColor: context.reem.text,
              unselectedLabelColor: context.reem.textMuted,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              dividerColor: context.reem.border,
              tabs: [for (final tab in _tabs) Tab(text: tab)],
            ),
            Expanded(
              child: _query.isEmpty
                  ? _buildIdle()
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTop(),
                        _buildUsers(),
                        _buildVideos(),
                        _comingSoon(Icons.photo_library_outlined, 'Photos', 'Les photos publiées sur REEM seront recherchables ici.'),
                        _comingSoon(Icons.live_tv_rounded, 'Live', 'Les lives arrivent bientôt sur REEM.'),
                        _comingSoon(Icons.music_note_rounded, 'Sons', 'La bibliothèque de sons arrive bientôt sur REEM.'),
                        _buildHashtags(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // Avant la recherche : recherches récentes et tendances
  Widget _buildIdle() {
    final recents = AppSettings.instance.recentSearches;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (recents.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text('Recherches récentes', style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              TextButton(
                onPressed: () => setState(() => AppSettings.instance.update(AppSettings.instance.recentSearches.clear)),
                child: const Text('Tout effacer'),
              ),
            ],
          ),
          for (final term in recents)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(Icons.history_rounded, color: context.reem.textMuted),
              title: Text(term, style: TextStyle(color: context.reem.text)),
              trailing: IconButton(
                icon: Icon(Icons.close_rounded, size: 18, color: context.reem.textMuted),
                onPressed: () => setState(() {
                  AppSettings.instance.update(() => recents.remove(term));
                }),
              ),
              onTap: () => _useSuggestion(term),
            ),
          const SizedBox(height: 14),
        ],
        Text('Tendances', style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 6),
        if (_trending.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Les hashtags populaires apparaîtront ici dès que des vidéos en utiliseront.',
              style: TextStyle(color: context.reem.textMuted, height: 1.35),
            ),
          )
        else
          for (var i = 0; i < _trending.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(Icons.trending_up_rounded, color: ReemColors.like),
              title: Text('#${_trending[i]['tag']}', style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${_trending[i]['videos_count']} vidéo${(_trending[i]['videos_count'] ?? 0) > 1 ? 's' : ''}',
                style: TextStyle(color: context.reem.textMuted),
              ),
              onTap: () => _useSuggestion('#${_trending[i]['tag']}'),
            ),
      ],
    );
  }

  Widget _comingSoon(IconData icon, String title, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: context.reem.textMuted),
            const SizedBox(height: 14),
            Text(title, style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: context.reem.textMuted, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _empty(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: context.reem.textMuted, height: 1.4)),
      ),
    );
  }

  Widget _loader() => const Center(child: CircularProgressIndicator());

  // ---- Top ----

  Widget _buildTop() {
    if (_loading.contains('top') || !_cache.containsKey('top')) return _loader();
    final results = _cache['top']!;
    if (results.isEmpty) return _empty('Aucun résultat pour « $_query ».');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        if (results.users.isNotEmpty) ...[
          _sectionTitle('Utilisateurs', onMore: () => _tabController.animateTo(1)),
          for (final user in results.users.take(3)) _userRow(user),
          const SizedBox(height: 10),
        ],
        if (results.hashtags.isNotEmpty) ...[
          _sectionTitle('Hashtags', onMore: () => _tabController.animateTo(6)),
          for (final tag in results.hashtags.take(3)) _hashtagRow(tag),
          const SizedBox(height: 10),
        ],
        if (results.videos.isNotEmpty) ...[
          _sectionTitle('Vidéos', onMore: () => _tabController.animateTo(2)),
          _videoGrid(results.videos, shrink: true),
        ],
      ],
    );
  }

  Widget _sectionTitle(String title, {required VoidCallback onMore}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          TextButton(onPressed: onMore, child: const Text('Voir tout')),
        ],
      ),
    );
  }

  // ---- Utilisateurs ----

  Widget _buildUsers() {
    if (_loading.contains('users') || !_cache.containsKey('users')) return _loader();
    final users = _cache['users']!.users;
    if (users.isEmpty) return _empty('Aucun utilisateur trouvé pour « $_query ».');

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      itemCount: users.length,
      itemBuilder: (context, index) => _userRow(users[index]),
    );
  }

  Widget _userRow(Map<String, dynamic> user) {
    final photo = absoluteMediaUrl(user['profile_photo_path']?.toString());
    final name = '${user['name'] ?? ''}';
    final username = (user['username'] ?? '').toString();
    final followers = int.tryParse('${user['followers_count']}') ?? 0;
    final following = _isFollowing(user);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: context.reem.surfaceHigh,
        backgroundImage: photo != null ? NetworkImage(photo) : null,
        child: photo == null
            ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w700))
            : null,
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w700)),
      subtitle: Text(
        '${username.isNotEmpty ? '@$username · ' : ''}$followers abonné${followers > 1 ? 's' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.reem.textMuted, fontSize: 12.5),
      ),
      trailing: SizedBox(
        width: 96,
        child: ElevatedButton(
          onPressed: () => _toggleFollow(user),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 8),
            backgroundColor: following ? context.reem.surfaceHigh : ReemColors.primary,
            foregroundColor: following ? context.reem.text : Colors.white,
          ),
          child: Text(following ? 'Abonné(e)' : 'Suivre', style: const TextStyle(fontSize: 13)),
        ),
      ),
      onTap: () => _openProfile(user),
    );
  }

  // ---- Vidéos ----

  Widget _buildVideos() {
    if (_loading.contains('videos') || !_cache.containsKey('videos')) return _loader();
    final videos = _cache['videos']!.videos;
    if (videos.isEmpty) return _empty('Aucune vidéo trouvée pour « $_query ».');

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      child: _videoGrid(videos, shrink: true),
    );
  }

  Widget _videoGrid(List<Map<String, dynamic>> videos, {bool shrink = false}) {
    return GridView.builder(
      shrinkWrap: shrink,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 8,
        childAspectRatio: 0.6,
      ),
      itemCount: videos.length,
      itemBuilder: (context, index) => _videoTile(videos[index]),
    );
  }

  Widget _videoTile(Map<String, dynamic> video) {
    final thumbnail = videoThumbnailUrl(video);
    final user = video['user'] is Map ? video['user'] as Map : const {};
    final title = '${video['title'] ?? ''}';

    return GestureDetector(
      onTap: () => _openVideo(video),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: context.reem.surface),
                  VideoThumbnail(
                      thumbnailUrl: thumbnail ?? '',
                      videoUrl: (video['video_path'] ?? '').toString(),
                    ),
                  const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 38)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (title.isNotEmpty)
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.reem.text, fontSize: 13, height: 1.25)),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: Text(
                  '@${user['name'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.reem.textMuted, fontSize: 12),
                ),
              ),
              const Icon(Icons.favorite_rounded, color: ReemColors.like, size: 13),
              const SizedBox(width: 3),
              Text('${video['likes_count'] ?? 0}', style: TextStyle(color: context.reem.textSecondary, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  // ---- Hashtags ----

  Widget _buildHashtags() {
    if (_loading.contains('hashtags') || !_cache.containsKey('hashtags')) return _loader();
    final tags = _cache['hashtags']!.hashtags;
    if (tags.isEmpty) return _empty('Aucun hashtag trouvé pour « $_query ».');

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      itemCount: tags.length,
      itemBuilder: (context, index) => _hashtagRow(tags[index]),
    );
  }

  Widget _hashtagRow(Map<String, dynamic> tag) {
    final count = int.tryParse('${tag['videos_count']}') ?? 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: context.reem.surfaceHigh,
        child: Icon(Icons.tag_rounded, color: context.reem.text),
      ),
      title: Text('#${tag['tag']}', style: TextStyle(color: context.reem.text, fontWeight: FontWeight.w700)),
      subtitle: Text('$count vidéo${count > 1 ? 's' : ''}', style: TextStyle(color: context.reem.textMuted)),
      onTap: () {
        // Les vidéos qui utilisent ce hashtag
        _controller.text = '#${tag['tag']}';
        _submit('#${tag['tag']}');
        _tabController.animateTo(2);
      },
    );
  }
}
