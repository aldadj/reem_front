import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/platform_helper.dart';
import '../theme/reem_theme.dart';
import '../utils/media_url.dart';
import '../services/app_settings.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';
import 'package:http/http.dart' as http;
// import 'package:image_picker/image_picker.dart'; // Commenté pour désactiver la sélection d'image
import '../services/session_manager.dart';
import '../services/auth_service.dart';
import '../widgets/video_player_item.dart';
import '../widgets/video_thumbnail.dart';
import '../widgets/video_search_dialog.dart';
import 'search_screen.dart';
import '../models/video.dart' as app_models;
import 'upload_screen.dart';
import 'auth_screen.dart';
import 'login_screen.dart';
import 'messages_screen.dart';

import 'story_viewer_screen.dart';
import '../services/story_service.dart';
import '../widgets/story_bar.dart';
import '../widgets/reem_nav_bar.dart';


class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<dynamic> _videos = [];
  List<dynamic> _friendsVideos = [];
  List<dynamic> _followingVideos = []; // vidéos des comptes que je suis
  List<dynamic> _exploreVideos = [];
  List<dynamic> _userVideos = [];
  List<StoryGroup> _storyGroups = [];
  bool _isLoading = true;
  bool _isLoadingExplore = false;
  bool _isLoadingUserVideos = false;
  bool _isUpdatingPhoto = false;
  int _currentIndex = 0;
  int _profileTabIndex = 0;
  int _currentBottomIndex = 0;
  int _desktopSection = 0;
  int _mobileFeedTabIndex = 2;
  bool _isDesktopMenuOpen = false;
  bool _isSidebarCollapsed = false;
  
  // Le mode clair / sombre est global (Paramètres) : on le lit depuis le thème
  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;
  bool _isEnglish = false;
  int _unreadNotificationsCount = 0;
  List<String> get _recentSearches => AppSettings.instance.recentSearches;
  final PageController _feedPageController = PageController();
  late PageController _mobileTabsController;
  bool _tabsControllerAuth = false;
  final List<PageController> _mobileVideoControllers = [PageController(), PageController(), PageController(), PageController()];
  final List<int> _mobileVideoIndices = [0, 0, 0, 0];
  final List<ValueNotifier<bool>> _mobileTabVisibility = [
    ValueNotifier<bool>(false),
    ValueNotifier<bool>(false),
    ValueNotifier<bool>(true),
    ValueNotifier<bool>(false),
  ];
  final ValueNotifier<int> _visibleVideoIndex = ValueNotifier<int>(0);
  final ValueNotifier<bool> _isFeedVisible = ValueNotifier<bool>(true);
  final SessionManager _sessionManager = SessionManager();
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _tabsControllerAuth = _sessionManager.isAuthenticated;
    _mobileTabsController = PageController(initialPage: _tabsControllerAuth ? 2 : 1);
    _fetchVideos();
    _fetchUnreadNotificationsCount();
    if (_sessionManager.isAuthenticated) _fetchStories();
  }

  Future<void> _fetchVideos() async {
    setState(() => _isLoading = true);
    final String apiUrl = "${AuthService.baseUrl}/videos?per_page=20";
    try {
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: _sessionManager.isAuthenticated
            ? {'Authorization': 'Bearer ${_sessionManager.authToken}'}
            : null,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final videos = List<dynamic>.from(data['data'] ?? []);
        videos.shuffle();
        setState(() {
          _videos = videos;
          _isLoading = false;
        });
        _resetFeedPosition(2);
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print("Erreur lors de la récupération des vidéos : $e");
      setState(() { _isLoading = false; });
    }
  }

  // Après une actualisation : on revient à la première vidéo et elle se lance toute seule
  void _resetFeedPosition(int tab) {
    _mobileVideoIndices[tab] = 0;
    final isActive = (tab == 2 && _currentBottomIndex == 0 && _mobileFeedTabIndex == 2) ||
        (tab == 3 && _currentBottomIndex == 0 && _mobileFeedTabIndex == 3) ||
        (tab == 1 && _currentBottomIndex == 1);
    if (!isActive) return;
    _currentIndex = 0;
    _visibleVideoIndex.value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_feedPageController.hasClients) _feedPageController.jumpToPage(0);
    });
  }

  Future<void> _fetchUserVideos() async {
    if (!_sessionManager.isAuthenticated) return;
    
    setState(() => _isLoadingUserVideos = true);
    final String apiUrl = "${AuthService.baseUrl}/user/videos";
    
    try {
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {'Authorization': 'Bearer ${_sessionManager.authToken}'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _userVideos = data; 
        });
      }
    } catch (e) {
      print("Erreur vidéos utilisateur : $e");
    } finally {
      setState(() => _isLoadingUserVideos = false);
    }
  }

  Future<void> _fetchFriendsVideos() async {
    if (!_sessionManager.isAuthenticated) {
      setState(() => _friendsVideos = []);
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/videos/friends'),
        headers: {'Authorization': 'Bearer ${_sessionManager.authToken}'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final videos = List<dynamic>.from(data['data'] ?? []);
        setState(() {
          _friendsVideos = videos;
        });
        _resetFeedPosition(1);
      }
    } catch (e) {
      print('Erreur amis vidéos : $e');
    }
  }

  Future<void> _fetchFollowingVideos() async {
    if (!_sessionManager.isAuthenticated) {
      setState(() => _followingVideos = []);
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/videos/following'),
        headers: {'Authorization': 'Bearer ${_sessionManager.authToken}'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final videos = List<dynamic>.from(data['data'] ?? []);
        setState(() {
          _followingVideos = videos;
        });
        _resetFeedPosition(3);
      }
    } catch (e) {
      print('Erreur vidéos suivies : $e');
    }
  }

  Future<void> _fetchStories() async {
    final groups = await StoryService().fetchStories();
    if (mounted) setState(() => _storyGroups = groups);
  }

  Future<void> _openStoryViewer(int index) async {
    _isFeedVisible.value = false;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryViewerScreen(groups: _storyGroups, startGroup: index),
      ),
    );
    if (!mounted) return;
    _isFeedVisible.value = true;
    _fetchStories();
  }

  Future<void> _addStory() async {
    final posted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const UploadScreen(storyMode: true)),
    );
    if (posted == true) _fetchStories();
  }

  Future<void> _fetchExploreVideos() async {
    setState(() => _isLoadingExplore = true);
    final String apiUrl = "${AuthService.baseUrl}/videos?per_page=40&order=recent";

    try {
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: _sessionManager.isAuthenticated
            ? {'Authorization': 'Bearer ${_sessionManager.authToken}'}
            : null,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _exploreVideos = data['data'] ?? [];
        });
      }
    } catch (e) {
      print("Erreur exploration vidéos : $e");
    } finally {
      setState(() => _isLoadingExplore = false);
    }
  }

  Future<void> _fetchUnreadNotificationsCount() async {
    if (!_sessionManager.isAuthenticated) {
      setState(() => _unreadNotificationsCount = 0);
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/notifications'),
        headers: {
          'Authorization': 'Bearer ${_sessionManager.authToken}',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> notifications = jsonDecode(response.body);
        final int count = notifications.where((notification) {
          return notification['read_at'] == null;
        }).length;
        setState(() => _unreadNotificationsCount = count);
      }
    } catch (e) {
      print('Erreur récupération notifications non lues : $e');
    }
  }

  void _updateUnreadNotificationsCount(int count) {
    setState(() => _unreadNotificationsCount = count);
  }

  void _selectDesktopSection(int section) {
    setState(() {
      _desktopSection = section;
      _isDesktopMenuOpen = false;
      _currentBottomIndex = switch (section) {
        0 || 1 => 0,
        2 || 3 => 1,
        4 || 5 => 3,
        _ => 4,
      };
      _isFeedVisible.value = section <= 3;
      for (final visibility in _mobileTabVisibility) {
        visibility.value = false;
      }
      _currentIndex = 0;
      _visibleVideoIndex.value = 0;
    });
    if (_feedPageController.hasClients) _feedPageController.jumpToPage(0);

    switch (section) {
      case 0:
        _fetchVideos();
        break;
      case 1:
        _fetchExploreVideos();
        if (_sessionManager.isAuthenticated) _fetchStories();
        break;
      case 2:
        _fetchFollowingVideos();
        break;
      case 3:
        _fetchFriendsVideos();
        break;
      case 4:
      case 5:
        _fetchUnreadNotificationsCount();
        break;
      case 6:
        if (_sessionManager.isAuthenticated) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const UploadScreen())).then((_) => _fetchVideos());
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AuthScreen()));
        }
        break;
      case 7:
        _fetchUserVideos();
        _fetchExploreVideos();
        break;
    }
  }

  void _activateMobileFeedTab(int index, {bool animate = false}) {
    final visibleTabs = _visibleMobileTabIds;
    final pageIndex = visibleTabs.indexOf(index);
    if (pageIndex < 0) return;
    if (animate && _mobileTabsController.hasClients && _mobileTabsController.page?.round() != pageIndex) {
      _mobileTabsController.animateToPage(pageIndex, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    }
    setState(() {
      _mobileFeedTabIndex = index;
      _currentBottomIndex = index == 1 ? 1 : 0;
      _visibleVideoIndex.value = _mobileVideoIndices[index];
      for (var tab = 0; tab < _mobileTabVisibility.length; tab++) {
        _mobileTabVisibility[tab].value = tab == index;
      }
    });
    if (index == 0 && _exploreVideos.isEmpty) _fetchExploreVideos();
    if (index == 0 && _sessionManager.isAuthenticated) _fetchStories();
    if (index == 1 && _friendsVideos.isEmpty) _fetchFriendsVideos();
    if (index == 2 && _videos.isEmpty) _fetchVideos();
    if (index == 3 && _followingVideos.isEmpty) _fetchFollowingVideos();
  }

  // Accueil : Communauté | Pour toi.  Amis : un écran à part (titre « Amis » seulement)
  List<int> get _visibleMobileTabIds => _currentBottomIndex == 1
      ? const [1]
      : (_sessionManager.isAuthenticated ? const [0, 3, 2] : const [0, 2]);

  Future<void> _openLoginScreen() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    if (!mounted) return;
    if (!_sessionManager.isAuthenticated) return;
    setState(() {
      _mobileFeedTabIndex = 2;
    });
    _fetchVideos();
    _fetchFollowingVideos();
    _fetchUnreadNotificationsCount();
    _fetchStories();
  }

  void _showDesktopSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SettingsScreen(onLogout: _logout)),
    );
  }

  void _showDesktopInfo(String title) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(_isEnglish ? 'This section is not available yet.' : 'Cette rubrique sera bientôt disponible.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(_isEnglish ? 'Close' : 'Fermer'))],
      ),
    );
  }

  Widget _buildDesktopSidebar() {
    final sidebarColor = context.reem.sidebar;
    final textColor = context.reem.text;
    final navItems = <(IconData, String, int)>[
      (Icons.home_filled, _isEnglish ? 'For you' : 'Pour toi', 0),
      (Icons.grid_view_rounded, _isEnglish ? 'Community' : 'Communauté', 1),
      if (_sessionManager.isAuthenticated) (Icons.person_add_alt_1_outlined, _isEnglish ? 'Following' : 'Suivis', 2),
      (Icons.group_outlined, _isEnglish ? 'Friends' : 'Amis', 3),
      (Icons.forum_outlined, _isEnglish ? 'Messages' : 'Messages', 4),
      (Icons.notifications_none, _isEnglish ? 'Activity' : 'Activité', 5),
      (Icons.video_call_outlined, _isEnglish ? 'Upload' : 'Importer', 6),
      (Icons.person_outline, _isEnglish ? 'Profile' : 'Profil', 7),
    ];

    return Container(
      width: _isSidebarCollapsed ? 76 : 248,
      color: sidebarColor,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(_isSidebarCollapsed ? 0 : 14, 6, _isSidebarCollapsed ? 0 : 8, 24),
            child: _isSidebarCollapsed
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.play_circle_fill, color: ReemColors.primary, size: 26),
                      IconButton(
                        tooltip: 'Développer le menu',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(width: 26, height: 32),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _isSidebarCollapsed = false),
                        icon: Icon(Icons.chevron_right, color: textColor, size: 20),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      const Icon(Icons.play_circle_fill, color: ReemColors.primary, size: 30),
                      const SizedBox(width: 10),
                      Text('REEM', style: TextStyle(color: textColor, fontSize: 22, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Réduire le menu',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() {
                          _isSidebarCollapsed = true;
                          _isDesktopMenuOpen = false;
                        }),
                        icon: Icon(Icons.chevron_left, color: textColor),
                      ),
                    ],
                  ),
          ),
          if (_isSidebarCollapsed)
            IconButton(tooltip: _isEnglish ? 'Search' : 'Rechercher', onPressed: _searchVideos, icon: Icon(Icons.search, color: textColor))
          else
            OutlinedButton.icon(
              onPressed: _searchVideos,
              icon: const Icon(Icons.search),
              label: Text(_isEnglish ? 'Search' : 'Rechercher'),
              style: OutlinedButton.styleFrom(foregroundColor: textColor, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
            ),
          const SizedBox(height: 18),
          Expanded(
            child: ListView.builder(
              itemCount: navItems.length,
              itemBuilder: (context, index) {
                final item = navItems[index];
                final selected = _desktopSection == item.$3;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    selected: selected,
                    selectedTileColor: context.reem.text.withValues(alpha: 0.08),
                    contentPadding: EdgeInsets.symmetric(horizontal: _isSidebarCollapsed ? 0 : 12),
                    minLeadingWidth: _isSidebarCollapsed ? 0 : 40,
                    horizontalTitleGap: _isSidebarCollapsed ? 0 : 8,
                    leadingAndTrailingTextStyle: TextStyle(color: textColor),
                    leading: Tooltip(message: item.$2, child: Icon(item.$1, color: selected ? ReemColors.primary : textColor)),
                    title: _isSidebarCollapsed ? null : Text(item.$2, style: TextStyle(color: textColor, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                    trailing: !_isSidebarCollapsed && item.$3 == 4 && _unreadNotificationsCount > 0
                        ? Text('$_unreadNotificationsCount', style: const TextStyle(color: ReemColors.primary))
                        : null,
                    onTap: () => _selectDesktopSection(item.$3),
                  ),
                );
              },
            ),
          ),
          if (_isDesktopMenuOpen)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: context.reem.surfaceHigh,
                border: Border.all(color: context.reem.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _buildMoreItem(Icons.settings_outlined, _isEnglish ? 'General settings' : 'Paramètres généraux', _showDesktopSettings, textColor),
                  _buildMoreItem(Icons.storefront_outlined, _isEnglish ? 'Sell on Reem' : 'Vendre sur Reem', () => _showDesktopInfo(_isEnglish ? 'Sell on Reem' : 'Vendre sur Reem'), textColor),
                  _buildMoreItem(Icons.campaign_outlined, _isEnglish ? 'Promote a post' : 'Promouvoir une publication', () => _showDesktopInfo(_isEnglish ? 'Promote a post' : 'Promouvoir une publication'), textColor),
                  _buildMoreItem(Icons.help_outline, _isEnglish ? 'Help center' : 'Centre d’aide', () => _showDesktopInfo(_isEnglish ? 'Help center' : 'Centre d’aide'), textColor),
                  if (_sessionManager.isAuthenticated)
                    _buildMoreItem(Icons.logout, _isEnglish ? 'Log out' : 'Déconnexion', _logout, textColor)
                  else
                    _buildMoreItem(Icons.login, _isEnglish ? 'Log in' : 'Connexion', _openLoginScreen, textColor),
                ],
              ),
            ),
          ListTile(
            dense: true,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: Icon(_isDesktopMenuOpen ? Icons.close : Icons.add, color: textColor),
            title: _isSidebarCollapsed ? null : Text(_isDesktopMenuOpen ? (_isEnglish ? 'Close menu' : 'Fermer le menu') : (_isEnglish ? 'More' : 'Plus'), style: TextStyle(color: textColor)),
            contentPadding: EdgeInsets.symmetric(horizontal: _isSidebarCollapsed ? 0 : 12),
            minLeadingWidth: _isSidebarCollapsed ? 0 : 40,
            horizontalTitleGap: _isSidebarCollapsed ? 0 : 8,
            onTap: () => setState(() {
              if (_isSidebarCollapsed) _isSidebarCollapsed = false;
              _isDesktopMenuOpen = !_isDesktopMenuOpen;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildMoreItem(IconData icon, String label, VoidCallback onTap, Color textColor) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: textColor),
      title: Text(label, style: TextStyle(color: textColor, fontSize: 13)),
      onTap: onTap,
    );
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text(
            'Déconnexion',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Êtes-vous sûr de vouloir vous déconnecter ?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () {
                _sessionManager.clearSession();
                Navigator.of(context).pop();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                );
              },
              child: const Text('Déconnexion', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _showPhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.white),
              title: const Text('Choisir une nouvelle photo', style: TextStyle(color: Colors.white)),
              // Appel à la fonction commentée désactivé
              onTap: null,
            ),
            if (_sessionManager.currentUser?['profile_photo_path'] != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Supprimer la photo actuelle', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _deletePhoto();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deletePhoto() async {
    setState(() => _isUpdatingPhoto = true);
    try {
      final response = await _authService.deleteProfilePhoto(_sessionManager.authToken!);
      if (response != null && response.containsKey('user')) {
        _sessionManager.setUser(response['user']);
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo supprimée')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    } finally {
      setState(() => _isUpdatingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 1120;
    return Theme(
      data: Theme.of(context),
      child: Scaffold(
      backgroundColor: context.reem.background,
      extendBodyBehindAppBar: false,
      extendBody: false,

      appBar: null,

      body: isDesktop
          ? Row(
              children: [
                _buildDesktopSidebar(),
                VerticalDivider(width: 1, color: context.reem.border),
                Expanded(child: _buildDesktopContent()),
              ],
            )
          : Stack(
              children: [
                Positioned.fill(
                  child: _currentBottomIndex == 4
                      ? SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: EdgeInsets.only(bottom: reemNavInset(context) - 8),
                            child: _buildProfileScreen(),
                          ),
                        )
                      : _currentBottomIndex == 3
                          ? SafeArea(
                              bottom: false,
                              child: MessagesScreen(
                                onUnreadCountChanged: _updateUnreadNotificationsCount,
                                bottomInset: reemNavInset(context),
                              ),
                            )
                          : _buildMobileFeedScreen(),
                ),
                // Barre flottante : ne prend plus toute la largeur, fond de verre transparent
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ReemNavBar(
                    currentIndex: _currentBottomIndex,
                    messagesBadge: _unreadNotificationsCount,
                    onTap: _handleBottomTap,
                  ),
                ),
              ],
            ),
      ),
    );
  }

  void _handleBottomTap(int index) {
      ReemNavController.hidden.value = false;
      if (index == 2) {
        // Vérifier si l'utilisateur est connecté avant de publier
        if (_sessionManager.isAuthenticated) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const UploadScreen()),
          ).then((_) => _fetchVideos());
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AuthScreen()),
          );
        }
      } else {
        if (index == 0 || index == 1) {
          // On change d'abord l'écran actif : les onglets visibles en dépendent
          setState(() => _currentBottomIndex = index);
          _isFeedVisible.value = true;
          final tab = index == 1 ? 1 : 2;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final pageIndex = _visibleMobileTabIds.indexOf(tab);
            if (_mobileTabsController.hasClients && pageIndex >= 0) {
              _mobileTabsController.jumpToPage(pageIndex);
            }
            _activateMobileFeedTab(tab);
          });
          // Chaque appui (même sur l'écran déjà ouvert) actualise : ordre aléatoire / amis à jour
          if (index == 1) {
            _fetchFriendsVideos();
          } else {
            _fetchVideos();
          }
        } else {
          _isFeedVisible.value = false;
          for (final visibility in _mobileTabVisibility) {
            visibility.value = false;
          }
        }

        setState(() {
          _currentBottomIndex = index;
          if (index == 3) {
            _fetchUnreadNotificationsCount();
          }
          if (index == 4) {
            _fetchUserVideos();
            _fetchExploreVideos();
          }
        });
      }
  }

  Widget _buildMobileFeedScreen() {
    if (_tabsControllerAuth != _sessionManager.isAuthenticated) {
      _tabsControllerAuth = _sessionManager.isAuthenticated;
      final old = _mobileTabsController;
      _mobileTabsController = PageController(initialPage: _tabsControllerAuth ? 2 : 1);
      _mobileFeedTabIndex = 2;
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    final visibleTabs = _visibleMobileTabIds;
    final tabLabels = {
      0: 'Communauté',
      1: 'Amis',
      3: 'Suivis',
      2: 'Pour toi',
    };
    return Stack(
      children: [
        Positioned.fill(
          child: PageView.builder(
            key: ValueKey('tabs_${_currentBottomIndex == 1 ? 'amis' : 'accueil'}_${_sessionManager.isAuthenticated}'),
            controller: _mobileTabsController,
            itemCount: visibleTabs.length,
            onPageChanged: (page) => _activateMobileFeedTab(visibleTabs[page]),
            itemBuilder: (context, page) => _buildMobileVideoPage(visibleTabs[page]),
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 6,
          left: 0,
          right: 0,
          child: SizedBox(
            height: 46,
            child: Stack(
              children: [
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(visibleTabs.length, (index) {
                      final tab = visibleTabs[index];
                      final selected = _mobileFeedTabIndex == tab;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _activateMobileFeedTab(tab, animate: true),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 180),
                                style: TextStyle(
                                  color: (_currentBottomIndex == 0 && _mobileFeedTabIndex == 0)
                                      ? (selected ? context.reem.text : context.reem.textMuted)
                                      : (selected ? Colors.white : Colors.white60),
                                  fontSize: selected ? 17 : 16,
                                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                                  shadows: (_currentBottomIndex == 0 && _mobileFeedTabIndex == 0) ? null : reemTextShadow,
                                ),
                                child: Text(tabLabels[tab]!),
                              ),
                              const SizedBox(height: 4),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                width: selected ? 24 : 0,
                                height: 3,
                                decoration: BoxDecoration(
                                  gradient: ReemColors.gradient,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                Positioned(
                  right: 6,
                  top: 0,
                  bottom: 0,
                  child: IconButton(
                    tooltip: 'Rechercher une vidéo',
                    onPressed: _searchVideos,
                    icon: Icon(
                      Icons.search_rounded,
                      color: (_currentBottomIndex == 0 && _mobileFeedTabIndex == 0) ? context.reem.text : Colors.white,
                      size: 28,
                      shadows: (_currentBottomIndex == 0 && _mobileFeedTabIndex == 0) ? null : reemTextShadow,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileVideoPage(int tab) {
    if (tab == 0) return _buildCommunityGrid(overlayTop: true);

    final videos = switch (tab) {
      0 => _exploreVideos,
      1 => _friendsVideos,
      3 => _followingVideos,
      _ => _videos,
    };
    final isLoading = switch (tab) {
      0 => _isLoadingExplore,
      1 => false,
      _ => _isLoading,
    };
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF8F55FF)));
    }
    if (videos.isEmpty) return _buildEmptyState(friends: tab == 1, following: tab == 3);

    return PageView.builder(
      controller: _mobileVideoControllers[tab],
      scrollDirection: Axis.vertical,
      itemCount: videos.length,
      onPageChanged: (index) {
        _mobileVideoIndices[tab] = index;
        if (tab == _mobileFeedTabIndex) _visibleVideoIndex.value = index;
      },
      itemBuilder: (context, index) => VideoPlayerItem(
        isFeedItem: true,
        video: _toVideoModel(Map<String, dynamic>.from(videos[index] as Map)),
        feedVisible: _mobileTabVisibility[tab],
        visibleVideoIndex: _visibleVideoIndex,
        itemIndex: index,
        onAutoNext: () {
          final pageController = _mobileVideoControllers[tab];
          if (!pageController.hasClients) return;
          if (index + 1 < videos.length) {
            pageController.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
          } else {
            pageController.animateToPage(0, duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
          }
        },
        showBackButton: false,
      ),
    );
  }

  Widget _buildDesktopContent() {
    switch (_desktopSection) {
      case 1:
        return _buildCommunityGrid(overlayTop: false);
      case 2:
      case 3:
        return Stack(
          children: [
            _buildFeedScreen(),
            Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Text(
                    _desktopSection == 2 ? 'Suivis' : 'Amis',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, shadows: reemTextShadow),
                  ),
                ),
              ),
            ),
          ],
        );
      case 4:
      case 5:
        return MessagesScreen(onUnreadCountChanged: _updateUnreadNotificationsCount);
      case 7:
        return _buildProfileScreen();
      default:
        return _buildFeedScreen();
    }
  }

  Widget _buildFeedScreen({bool forceExplore = false}) {
    if (forceExplore ? _isLoadingExplore : _isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF8F55FF)));
    }

    final List<dynamic> sourceVideos = forceExplore
        ? _exploreVideos
        : _currentBottomIndex == 1
            ? (_desktopSection == 2 ? _followingVideos : _friendsVideos)
            : _videos;

    if (sourceVideos.isEmpty) {
      return _buildEmptyState();
    }

    final shuffledVideos = List<dynamic>.from(sourceVideos);

    return RefreshIndicator(
        onRefresh: forceExplore
          ? _fetchExploreVideos
          : _currentBottomIndex == 1
            ? (_desktopSection == 2 ? _fetchFollowingVideos : _fetchFriendsVideos)
            : _fetchVideos,
      color: const Color(0xFF8F55FF),
      child: PageView.builder(
        controller: _feedPageController,
        scrollDirection: Axis.vertical,
        itemCount: shuffledVideos.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
            _visibleVideoIndex.value = index;
          });
        },
        itemBuilder: (context, index) {
          final video = shuffledVideos[index];
          return VideoPlayerItem(
            isFeedItem: true,
            video: _toVideoModel(video),
            feedVisible: _isFeedVisible,
            visibleVideoIndex: _visibleVideoIndex,
            itemIndex: index,
            onAutoNext: () {
              if (!_feedPageController.hasClients) return;
              final nextIndex = index + 1 < shuffledVideos.length ? index + 1 : 0;
              if (nextIndex == 0) {
                _feedPageController.animateToPage(
                  0,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOut,
                );
              } else {
                _feedPageController.nextPage(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOut,
                );
              }
            },
            showBackButton: false,
          );
        },
      ),
    );
  }

  app_models.Video _toVideoModel(Map<String, dynamic> video) {
    final String rawPath = (video['video_path'] ?? '').toString();
    final String cleanPath = rawPath.replaceAll('\\', '/');
    final String serverBaseUrl = AuthService.baseUrl.replaceFirst(RegExp(r'/api$'), '');
    final String fullVideoUrl = cleanPath.startsWith('http')
        ? cleanPath
        : '$serverBaseUrl${cleanPath.startsWith('/') ? '' : '/'}$cleanPath';

    return app_models.Video(
      id: video['id'],
      videoUrl: fullVideoUrl,
      title: video['title'] ?? '',
      description: video['description'],
      username: video['user'] != null ? video['user']['name'] : 'Anonyme',
      authorProfilePhotoUrl: video['user'] != null ? video['user']['profile_photo_path']?.toString() : null,
      isAuthorFollowed: video['author_is_followed'] == true,
      authorId: video['user'] != null ? video['user']['id'] ?? 0 : 0,
      likesCount: video['likes_count'] ?? 0,
      commentsCount: video['comments_count'] ?? 0,
      isLiked: video['liked_by_user'] ?? false,
      isFavorited: video['favorited_by_user'] ?? false,
    );
  }

  Future<void> _searchVideos() async {
    _isFeedVisible.value = false;
    for (final visibility in _mobileTabVisibility) {
      visibility.value = false;
    }

    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));

    if (!mounted) return;
    _isFeedVisible.value = true;
    if (_currentBottomIndex == 0 || _currentBottomIndex == 1) {
      _mobileTabVisibility[_mobileFeedTabIndex].value = true;
    }
  }

  Widget _buildProfileAvatar(Map<String, dynamic>? user) {
    String? photoPath = user?['profile_photo_path'];
    if (photoPath != null) {
      if (isAndroidPlatform && (photoPath.contains('localhost') || photoPath.contains('127.0.0.1'))) {
        photoPath = photoPath.replaceAll('localhost', '10.0.2.2').replaceAll('127.0.0.1', '10.0.2.2');
      }
      if (!photoPath.startsWith('http')) {
        final domain = AuthService.baseUrl.replaceFirst(RegExp(r'/api$'), '');
        photoPath = domain + (photoPath.startsWith('/') ? '' : '/') + photoPath;
      }
    }

    return Stack(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey[800],
            border: Border.all(color: Colors.white, width: 2),
            image: photoPath != null 
              ? DecorationImage(image: NetworkImage(photoPath), fit: BoxFit.cover) 
              : null,
          ),
          child: _isUpdatingPhoto 
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : (photoPath == null ? const Icon(Icons.person, size: 60, color: Colors.white) : null),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: _isUpdatingPhoto ? null : _showPhotoOptions,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt, size: 18, color: Colors.black),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileScreen() {
    final user = _sessionManager.currentUser;
    final bool isGuest = !_sessionManager.isAuthenticated;

    if (isGuest) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_outline, size: 80, color: Colors.grey),
              const SizedBox(height: 24),
              Text(
                "Inscrivez-vous pour voir votre profil",
                textAlign: TextAlign.center,
                style: TextStyle(color: context.reem.text, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                "Créez un compte pour partager vos propres vidéos et interagir avec la communauté.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AuthScreen()),
                    );
                  },
                  child: const Text("S'inscrire / Se connecter"),
                ),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => SettingsScreen(onLogout: _logout)),
                ),
                icon: const Icon(Icons.settings_outlined, size: 20),
                label: const Text('Paramètres'),
              ),
            ],
          ),
        ),
      );
    }

    final dynamic rawId = user?['id'];
    final int? myId = rawId is int ? rawId : int.tryParse('$rawId');
    if (myId != null) {
      return ProfileScreen(
        key: ValueKey('profil_$myId'),
        userId: myId,
        embedded: true,
        onLogout: _logout,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 80),
          
          _buildProfileAvatar(user),
          const SizedBox(height: 24),

          // Nom utilisateur
          Text(
            user?['name'] ?? 'Utilisateur',
            style: TextStyle(
              color: context.reem.text,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // Email
          Text(
            user?['email'] ?? '',
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),

          // Stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatColumn(_userVideos.length.toString(), 'Publications'),
              _buildStatColumn('0', 'Abonné(e)s'),
              _buildStatColumn('0', 'Abonnements'),
            ],
          ),
          const SizedBox(height: 32),

          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _profileTabIndex = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _profileTabIndex == 0 ? context.reem.text : context.reem.border,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Publications',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _profileTabIndex == 0 ? Colors.black : context.reem.text,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _profileTabIndex = 1);
                    if (_exploreVideos.isEmpty) {
                      _fetchExploreVideos();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _profileTabIndex == 1 ? context.reem.text : context.reem.border,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Explorer',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _profileTabIndex == 1 ? Colors.black : context.reem.text,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (_profileTabIndex == 0) ...[
            _buildProfileList(
              title: 'Vos publications',
              items: _userVideos,
              isLoading: _isLoadingUserVideos,
            ),
          ] else ...[
            _buildProfileList(
              title: 'Vidéos aléatoires',
              items: _exploreVideos,
              isLoading: _isLoadingExplore,
            ),
          ],

          const SizedBox(height: 24),

          // Bouton Modifier le profil
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.reem.text,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                // TODO: Implémenter la modification du profil
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Fonctionnalité à venir')),
                );
              },
              child: const Text(
                'Modifier le profil',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Bouton Déconnexion
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _logout,
              child: const Text(
                'Déconnexion',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _isFeedVisible.dispose();
    _visibleVideoIndex.dispose();
    _feedPageController.dispose();
    _mobileTabsController.dispose();
    for (final controller in _mobileVideoControllers) {
      controller.dispose();
    }
    for (final visibility in _mobileTabVisibility) {
      visibility.dispose();
    }
    super.dispose();
  }

  Widget _buildProfileList({
    required String title,
    required List<dynamic> items,
    required bool isLoading,
  }) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
    }

    if (items.isEmpty) {
      return Column(
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            'Aucune vidéo trouvée.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(color: Colors.white24),
          itemBuilder: (context, index) {
            final video = items[index];
            final String rawPath = video['video_path'] ?? '';
            final String cleanPath = rawPath.replaceAll('\\', '/');

            final String thumbnailPath = video['thumbnail_path'] ?? '';

            final String serverBaseUrl =
                AuthService.baseUrl.replaceFirst(RegExp(r'/api$'), '');

            final String thumbnailUrl = thumbnailPath.startsWith('http')
                ? thumbnailPath
                : '$serverBaseUrl${thumbnailPath.startsWith('/') ? '' : '/'}$thumbnailPath';

            final String fullVideoUrl = cleanPath.startsWith('http')
                ? cleanPath
                : '$serverBaseUrl${cleanPath.startsWith('/') ? '' : '/'}$cleanPath';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 100,
                  height: 60,
                  child: VideoThumbnail(
                    thumbnailUrl: thumbnailUrl,
                    videoUrl: fullVideoUrl,
                  ),
                ),
              ),
              title: Text(video['title'] ?? 'Sans titre', style: const TextStyle(color: Colors.white)),
              subtitle: Text(video['description'] ?? '', style: const TextStyle(color: Colors.grey)),
              trailing: Text(
                '${video['likes_count'] ?? 0} ❤',
                style: const TextStyle(color: Colors.white70),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoPlayerItem(
                      video: app_models.Video(
                        id: video['id'],
                        videoUrl: fullVideoUrl,
                        title: video['title'] ?? '',
                        description: video['description'],
                        username: video['user'] != null ? video['user']['name'] : 'Anonyme',
                        authorProfilePhotoUrl: video['user'] != null ? video['user']['profile_photo_path']?.toString() : null,
                        isAuthorFollowed: video['author_is_followed'] == true,
                        authorId: video['user'] != null ? video['user']['id'] ?? 0 : 0,
                        likesCount: video['likes_count'] ?? 0,
                        commentsCount: video['comments_count'] ?? 0,
                        isLiked: video['liked_by_user'] ?? false,
                        isFavorited: video['favorited_by_user'] ?? false,
                      ),
                      feedVisible: _isFeedVisible,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  // Communauté : stories en haut, puis vidéos en grille, 2 par ligne (plus sur grand écran),
  // avec le compte, les j'aime et les commentaires sous chaque vidéo.
  Widget _buildCommunityGrid({required bool overlayTop}) {
    if (_isLoadingExplore && _exploreVideos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_exploreVideos.isEmpty) return _buildEmptyState();

    const topPadding = 8.0;

    return Column(
      children: [
        SizedBox(height: overlayTop ? MediaQuery.paddingOf(context).top + 56 : 0),
        if (_sessionManager.isAuthenticated)
          StoryBar(groups: _storyGroups, onOpen: _openStoryViewer, onAdd: _addStory),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1000 ? 4 : constraints.maxWidth >= 640 ? 3 : 2;
              return RefreshIndicator(
                onRefresh: () async {
                  await _fetchExploreVideos();
                  if (_sessionManager.isAuthenticated) await _fetchStories();
                },
                edgeOffset: topPadding,
                child: GridView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(10, topPadding, 10, reemNavInset(context) + 12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.6,
                  ),
                  itemCount: _exploreVideos.length,
                  itemBuilder: (context, index) => _buildCommunityTile(
                    Map<String, dynamic>.from(_exploreVideos[index] as Map),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String? _gridThumbnailUrl(Map<String, dynamic> video) {
    final raw = (video['thumbnail_path'] ?? '').toString();
    if (raw.isNotEmpty) return absoluteMediaUrl(raw);

    final path = (video['video_path'] ?? '').toString();
    if (path.contains('/video/upload/')) {
      return path
          .replaceFirst('/video/upload/', '/video/upload/so_0,w_480,h_800,c_fill,q_auto/')
          .replaceFirst(RegExp(r'\.(mp4|mov|avi|mkv|webm)$', caseSensitive: false), '.jpg');
    }
    return null;
  }

  void _openGridVideo(Map<String, dynamic> video) {
    final visible = ValueNotifier<bool>(true);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: VideoPlayerItem(video: _toVideoModel(video), feedVisible: visible),
        ),
      ),
    ).then((_) => visible.dispose());
  }

  Widget _buildCommunityTile(Map<String, dynamic> video) {
    final thumbnail = _gridThumbnailUrl(video);
    final user = video['user'] is Map ? video['user'] as Map : const {};
    final name = (user['name'] ?? 'Anonyme').toString();
    final likes = video['likes_count'] ?? 0;
    final comments = video['comments_count'] ?? 0;

    return GestureDetector(
      onTap: () => _openGridVideo(video),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: context.reem.surface),
                  VideoThumbnail(
                      thumbnailUrl: thumbnail ?? '',
                      videoUrl: (video['video_path'] ?? '').toString(),
                    ),
                  const Center(
                    child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 42),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '@$name',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.reem.text, fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              const Icon(Icons.favorite_rounded, color: ReemColors.like, size: 15),
              const SizedBox(width: 4),
              Text('$likes', style: TextStyle(color: context.reem.textSecondary, fontSize: 12.5)),
              const SizedBox(width: 14),
              Icon(Icons.chat_bubble_rounded, color: context.reem.textMuted, size: 14),
              const SizedBox(width: 4),
              Text('$comments', style: TextStyle(color: context.reem.textSecondary, fontSize: 12.5)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({bool friends = false, bool following = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: ReemColors.gradient,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(friends ? Icons.group_rounded : (following ? Icons.person_add_alt_1_rounded : Icons.videocam_rounded), color: Colors.white, size: 38),
            ),
            const SizedBox(height: 20),
            Text(
              friends ? 'Pas encore de vidéos d’amis' : (following ? 'Rien à voir pour l’instant' : 'Aucune vidéo disponible.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.reem.text, fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              friends
                  ? 'Tes amis sont les personnes que tu suis et qui te suivent aussi. Abonne-toi à des comptes pour en trouver.'
                  : (following
                      ? 'Abonne-toi à des créateurs : leurs vidéos apparaîtront ici, et seulement les leurs.'
                      : 'Publie une première vidéo pour alimenter ton fil.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.reem.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 22),
            if (!friends && !following)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const UploadScreen()),
                  ).then((_) => _fetchVideos());
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Publier une vidéo'),
              ),
          ],
        ),
      ),
    );
  }
}

class _VideoSearchDelegate extends SearchDelegate<Map<String, dynamic>?> {
  final List<dynamic> videos;
  final String? token;
  String _requestedQuery = '';
  Future<List<dynamic>>? _resultsFuture;

  _VideoSearchDelegate(this.videos, this.token);

  Future<List<dynamic>> _searchEveryPage(String term) async {
    final results = <dynamic>[];
    var page = 1;
    var lastPage = 1;
    do {
      final uri = Uri.parse('${AuthService.baseUrl}/videos').replace(
        queryParameters: {'search': term, 'page': '$page'},
      );
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode != 200) {
        throw Exception('La recherche est momentanément indisponible.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        results.addAll((decoded['data'] as List<dynamic>?) ?? []);
        lastPage = int.tryParse('${decoded['last_page']}') ?? page;
      } else if (decoded is List<dynamic>) {
        results.addAll(decoded);
        lastPage = page;
      }
      page++;
    } while (page <= lastPage);
    return results;
  }

  Future<List<dynamic>> _results() {
    final term = query.trim();
    if (_requestedQuery != term || _resultsFuture == null) {
      _requestedQuery = term;
      _resultsFuture = _searchEveryPage(term);
    }
    return _resultsFuture!;
  }

  @override
  String get searchFieldLabel => 'Titre, description ou auteur';

  @override
  ThemeData appBarTheme(BuildContext context) => Theme.of(context).copyWith(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0714),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F0A1C),
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          hintStyle: TextStyle(color: Colors.white54),
          border: InputBorder.none,
        ),
      );

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            tooltip: 'Effacer',
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        tooltip: 'Retour',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) {
    if (query.trim().isEmpty) {
      return const Center(child: Text('Saisissez un nom ou un sujet.', style: TextStyle(color: Colors.white70)));
    }
    return FutureBuilder<List<dynamic>>(
      future: _results(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}', style: const TextStyle(color: Colors.white70)));
        }
        final matches = snapshot.data ?? [];
        if (matches.isEmpty) {
          return const Center(child: Text('Aucune vidéo trouvée', style: TextStyle(color: Colors.white70)));
        }
        return ListView.separated(
          itemCount: matches.length,
          separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
          itemBuilder: (context, index) {
            final video = Map<String, dynamic>.from(matches[index] as Map);
            final author = video['user'] is Map ? video['user']['name'] : 'Anonyme';
            final mediaUrl = _absoluteUrl(video['video_path'] ?? video['video_url']);
            final thumbnailUrl = _absoluteUrl(video['thumbnail_path']);
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              leading: SizedBox(
                width: 68,
                height: 104,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: VideoThumbnail(thumbnailUrl: thumbnailUrl, videoUrl: mediaUrl),
                ),
              ),
              title: Text(
                (video['title'] ?? 'Sans titre').toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '@$author\n${(video['description'] ?? '').toString()}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60),
              ),
              onTap: () => close(context, video),
            );
          },
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final term = query.trim().toLowerCase();
    if (term.isEmpty) return const SizedBox.shrink();
    final suggestions = videos.where((entry) {
      if (entry is! Map<String, dynamic>) return false;
      final author = entry['user'] is Map ? entry['user']['name'] : '';
      return '${entry['title'] ?? ''} ${entry['description'] ?? ''} $author'
          .toLowerCase()
          .contains(term);
    }).toList();
    if (suggestions.isEmpty) {
      return const Center(child: Text('Appuyez sur Entrée pour rechercher toutes les vidéos.', style: TextStyle(color: Colors.white70)));
    }
    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final video = Map<String, dynamic>.from(suggestions[index] as Map);
        final mediaUrl = _absoluteUrl(video['video_path'] ?? video['video_url']);
        return ListTile(
          leading: SizedBox(
            width: 52,
            height: 76,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: VideoThumbnail(
                thumbnailUrl: _absoluteUrl(video['thumbnail_path']),
                videoUrl: mediaUrl,
              ),
            ),
          ),
          title: Text((video['title'] ?? 'Sans titre').toString(), style: const TextStyle(color: Colors.white)),
          subtitle: const Text('Appuyez pour ouvrir', style: TextStyle(color: Colors.white60)),
          onTap: () => close(context, video),
        );
      },
    );
  }

  String _absoluteUrl(Object? rawValue) {
    final raw = rawValue?.toString() ?? '';
    if (raw.isEmpty || raw.startsWith('http')) return raw;
    final base = AuthService.baseUrl.replaceFirst(RegExp(r'/api$'), '');
    return '$base${raw.startsWith('/') ? '' : '/'}$raw';
  }
}
