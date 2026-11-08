import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
// import 'package:image_picker/image_picker.dart'; // Commenté pour désactiver la sélection d'image
import '../services/session_manager.dart';
import '../services/auth_service.dart';
import '../widgets/video_player_item.dart';
import '../widgets/video_thumbnail.dart';
import '../widgets/video_search_dialog.dart';
import '../models/video.dart' as app_models;
import 'upload_screen.dart';
import 'auth_screen.dart';
import 'login_screen.dart';
import 'messages_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<dynamic> _videos = [];
  List<dynamic> _friendsVideos = [];
  List<dynamic> _exploreVideos = [];
  List<dynamic> _userVideos = [];
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
  bool _isDarkMode = true;
  bool _isEnglish = false;
  int _unreadNotificationsCount = 0;
  final List<String> _recentSearches = [];
  final PageController _feedPageController = PageController();
  late final PageController _mobileTabsController;
  final List<PageController> _mobileVideoControllers = [PageController(), PageController(), PageController()];
  final List<int> _mobileVideoIndices = [0, 0, 0];
  final List<ValueNotifier<bool>> _mobileTabVisibility = [
    ValueNotifier<bool>(false),
    ValueNotifier<bool>(false),
    ValueNotifier<bool>(true),
  ];
  final ValueNotifier<int> _visibleVideoIndex = ValueNotifier<int>(0);
  final ValueNotifier<bool> _isFeedVisible = ValueNotifier<bool>(true);
  final SessionManager _sessionManager = SessionManager();
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _mobileTabsController = PageController(initialPage: _sessionManager.isAuthenticated ? 2 : 1);
    _fetchVideos();
    _fetchUnreadNotificationsCount();
  }

  Future<void> _fetchVideos() async {
    setState(() => _isLoading = true);
    final String apiUrl = "${AuthService.baseUrl}/videos";
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
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print("Erreur lors de la récupération des vidéos : $e");
      setState(() { _isLoading = false; });
    }
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
      }
    } catch (e) {
      print('Erreur amis vidéos : $e');
    }
  }

  Future<void> _fetchExploreVideos() async {
    setState(() => _isLoadingExplore = true);
    final String apiUrl = "${AuthService.baseUrl}/videos";

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
        break;
      case 2:
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
    if (index == 1 && _friendsVideos.isEmpty) _fetchFriendsVideos();
    if (index == 2 && _videos.isEmpty) _fetchVideos();
  }

  List<int> get _visibleMobileTabIds => _sessionManager.isAuthenticated ? const [0, 1, 2] : const [0, 2];

  Future<void> _openLoginScreen() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    if (!mounted) return;
    if (!_sessionManager.isAuthenticated) return;
    setState(() {
      _mobileFeedTabIndex = 2;
    });
    _fetchVideos();
    _fetchUnreadNotificationsCount();
  }

  void _showDesktopSettings() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_isEnglish ? 'General settings' : 'Paramètres généraux'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_isEnglish ? 'Dark mode' : 'Mode sombre'),
                value: _isDarkMode,
                onChanged: (value) {
                  setState(() => _isDarkMode = value);
                  setDialogState(() {});
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_isEnglish ? 'Language' : 'Langue'),
                trailing: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('FR')),
                    ButtonSegment(value: true, label: Text('EN')),
                  ],
                  selected: {_isEnglish},
                  onSelectionChanged: (values) {
                    setState(() => _isEnglish = values.first);
                    setDialogState(() {});
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_isEnglish ? 'Close' : 'Fermer')),
          ],
        ),
      ),
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
    final sidebarColor = _isDarkMode ? const Color(0xFF122D48) : const Color(0xFFEAF2F9);
    final textColor = _isDarkMode ? Colors.white : const Color(0xFF171717);
    final navItems = <(IconData, String, int)>[
      (Icons.home_filled, _isEnglish ? 'For you' : 'Pour toi', 0),
      (Icons.explore_outlined, _isEnglish ? 'Explore' : 'Explorer', 1),
      if (_sessionManager.isAuthenticated)
        (Icons.person_add_alt_1_outlined, _isEnglish ? 'Following' : 'Suivi', 2),
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
                      const Icon(Icons.play_circle_fill, color: Colors.redAccent, size: 26),
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
                      const Icon(Icons.play_circle_fill, color: Colors.redAccent, size: 30),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    selected: selected,
                    selectedTileColor: _isDarkMode ? const Color(0xFF254967) : const Color(0xFFD8E8F5),
                    contentPadding: EdgeInsets.symmetric(horizontal: _isSidebarCollapsed ? 0 : 12),
                    minLeadingWidth: _isSidebarCollapsed ? 0 : 40,
                    horizontalTitleGap: _isSidebarCollapsed ? 0 : 8,
                    leadingAndTrailingTextStyle: TextStyle(color: textColor),
                    leading: Tooltip(message: item.$2, child: Icon(item.$1, color: selected ? Colors.redAccent : textColor)),
                    title: _isSidebarCollapsed ? null : Text(item.$2, style: TextStyle(color: textColor, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                    trailing: !_isSidebarCollapsed && item.$3 == 4 && _unreadNotificationsCount > 0
                        ? Text('$_unreadNotificationsCount', style: const TextStyle(color: Colors.redAccent))
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
                color: _isDarkMode ? const Color(0xFF1A3A58) : Colors.white,
                border: Border.all(color: _isDarkMode ? Colors.white12 : Colors.black12),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  // Future<void> _pickAndUploadPhoto() async {
  //   final picker = ImagePicker();
  //   final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    
  //   if (pickedFile != null) {
  //     setState(() => _isUpdatingPhoto = true);
  //     try {
  //       final response = await _authService.updateProfilePhoto(
  //         _sessionManager.authToken!,
  //         pickedFile.path,
  //       );

  //       if (response != null && response.containsKey('user')) {
  //         _sessionManager.setUser(response['user']);
  //         setState(() {}); // Rafraîchir l'UI avec la nouvelle photo
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           const SnackBar(content: Text('Photo de profil mise à jour !')),
  //         );
  //       }
  //       } catch (e) {
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           SnackBar(content: Text('Erreur: $e')),
  //         );
  //       } finally {
  //         setState(() => _isUpdatingPhoto = false);
  //       }
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 1120;
    return Theme(
      data: _isDarkMode ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true),
      child: Scaffold(
      backgroundColor: _isDarkMode ? const Color(0xFF0B1A2E) : const Color(0xFFF3F4F6),
      extendBodyBehindAppBar: false,
      extendBody: false,

      appBar: isDesktop ? null : AppBar(
        backgroundColor: _isDarkMode ? const Color(0xFF0B1A2E) : const Color(0xFFF3F4F6),
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 0,
        leading: const SizedBox.shrink(),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF7C9BFF).withValues(alpha: _isDarkMode ? 0.16 : 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.auto_awesome, color: Color(0xFF7C9BFF), size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              "REEM",
              style: TextStyle(color: _isDarkMode ? Colors.white : const Color(0xFF132B45), fontWeight: FontWeight.w700, fontSize: 20),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(Icons.search_rounded, color: _isDarkMode ? Colors.white70 : const Color(0xFF132B45), size: 24),
            tooltip: 'Rechercher une vidéo',
            onPressed: _searchVideos,
          ),
          const SizedBox(width: 8),
        ],
      ),

      body: isDesktop
          ? Row(
              children: [
                _buildDesktopSidebar(),
                VerticalDivider(width: 1, color: _isDarkMode ? Colors.white12 : Colors.black12),
                Expanded(child: _buildDesktopContent()),
              ],
            )
          : _currentBottomIndex == 4
              ? _buildProfileScreen()
              : _currentBottomIndex == 3
                  ? MessagesScreen(onUnreadCountChanged: _updateUnreadNotificationsCount)
                : _buildMobileFeedScreen(),

      bottomNavigationBar: isDesktop ? null : BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF0F1628),
        elevation: 0,
        unselectedItemColor: Colors.white38,
        selectedItemColor: const Color(0xFF7C9BFF),
        selectedIconTheme: const IconThemeData(size: 24, color: Color(0xFF7C9BFF)),
        showSelectedLabels: true,
        showUnselectedLabels: false,
        currentIndex: _currentBottomIndex,
        onTap: (index) {
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
            if (index == 0) {
              _isFeedVisible.value = true;
              for (var tab = 0; tab < _mobileTabVisibility.length; tab++) {
                _mobileTabVisibility[tab].value = tab == 2;
              }
              _activateMobileFeedTab(2);
              _fetchVideos();
            } else if (index == 1) {
              _isFeedVisible.value = true;
              for (var tab = 0; tab < _mobileTabVisibility.length; tab++) {
                _mobileTabVisibility[tab].value = tab == 1;
              }
              _activateMobileFeedTab(1);
              _fetchFriendsVideos();
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
        },
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Accueil'),
          const BottomNavigationBarItem(icon: Icon(Icons.group_outlined), label: 'Ami(e)s'),
          BottomNavigationBarItem(
            icon: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF7C9BFF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
            ),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.forum_outlined),
                if (_unreadNotificationsCount > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFF7C9BFF),
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Text(
                        _unreadNotificationsCount > 99 ? '99+' : '$_unreadNotificationsCount',
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Messages',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profil'),
        ],
      ),
      ),
    );
  }

  Widget _buildMobileFeedScreen() {
    final visibleTabs = _visibleMobileTabIds;
    final tabLabels = {
      0: 'Communauté',
      1: 'Suivis',
      2: 'Pour toi',
    };
    return Stack(
      children: [
        Positioned.fill(
          child: PageView.builder(
            controller: _mobileTabsController,
            itemCount: visibleTabs.length,
            onPageChanged: (page) => _activateMobileFeedTab(visibleTabs[page]),
            itemBuilder: (context, page) => _buildMobileVideoPage(visibleTabs[page]),
          ),
        ),
        Positioned(
          top: 2,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(visibleTabs.length, (index) {
              final tab = visibleTabs[index];
              final selected = _mobileFeedTabIndex == tab;
              return InkWell(
                onTap: () => _activateMobileFeedTab(tab, animate: true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tabLabels[tab]!, style: TextStyle(color: selected ? Colors.white : Colors.white70, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, fontSize: 13, shadows: const [Shadow(color: Colors.black54, blurRadius: 5)])),
                      const SizedBox(height: 3),
                      Container(width: 22, height: 2, color: selected ? const Color(0xFF7C9BFF) : Colors.transparent),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileVideoPage(int tab) {
    final videos = switch (tab) {
      0 => _exploreVideos,
      1 => _friendsVideos,
      _ => _videos,
    };
    final isLoading = switch (tab) {
      0 => _isLoadingExplore,
      1 => false,
      _ => _isLoading,
    };
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF7C9BFF)));
    }
    if (videos.isEmpty) return _buildEmptyState();

    return PageView.builder(
      controller: _mobileVideoControllers[tab],
      scrollDirection: Axis.vertical,
      itemCount: videos.length,
      onPageChanged: (index) {
        _mobileVideoIndices[tab] = index;
        if (tab == _mobileFeedTabIndex) _visibleVideoIndex.value = index;
      },
      itemBuilder: (context, index) => VideoPlayerItem(
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
        return _buildFeedScreen(forceExplore: true);
      case 2:
      case 3:
        return _buildFeedScreen();
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
      return const Center(child: CircularProgressIndicator(color: Color(0xFF7C9BFF)));
    }

    final List<dynamic> sourceVideos = forceExplore
        ? _exploreVideos
        : _currentBottomIndex == 1
            ? _friendsVideos
            : _videos;

    if (sourceVideos.isEmpty) {
      return _buildEmptyState();
    }

    final shuffledVideos = List<dynamic>.from(sourceVideos);

    return RefreshIndicator(
        onRefresh: forceExplore
          ? _fetchExploreVideos
          : _currentBottomIndex == 1
            ? _fetchFriendsVideos
            : _fetchVideos,
      color: const Color(0xFF7C9BFF),
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
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: true,
      builder: (context) => VideoSearchDialog(
        token: _sessionManager.authToken,
        recentSearches: List<String>.unmodifiable(_recentSearches),
        onSearchSubmitted: (query) {
          setState(() {
            _recentSearches.removeWhere((item) => item.toLowerCase() == query.toLowerCase());
            _recentSearches.insert(0, query);
            if (_recentSearches.length > 8) _recentSearches.removeLast();
          });
        },
        onRemoveSearch: (query) => setState(() {
          _recentSearches.removeWhere((item) => item.toLowerCase() == query.toLowerCase());
        }),
        onClearSearches: () => setState(_recentSearches.clear),
      ),
    );
    if (!mounted) return;
    if (result == null) {
      _isFeedVisible.value = true;
      _mobileTabVisibility[_mobileFeedTabIndex].value = true;
      return;
    }

    final searchVideoVisible = ValueNotifier<bool>(true);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerItem(
          video: _toVideoModel(result),
          feedVisible: searchVideoVisible,
        ),
      ),
    );
    searchVideoVisible.dispose();
    if (mounted) {
      _isFeedVisible.value = true;
      _mobileTabVisibility[_mobileFeedTabIndex].value = true;
    }
  }

  Widget _buildProfileAvatar(Map<String, dynamic>? user) {
    String? photoPath = user?['profile_photo_path'];
    if (photoPath != null) {
      if (Platform.isAndroid && (photoPath.contains('localhost') || photoPath.contains('127.0.0.1'))) {
        photoPath = photoPath.replaceAll('localhost', '10.0.2.2').replaceAll('127.0.0.1', '10.0.2.2');
      }
      if (!photoPath.startsWith('http')) {
        final domain = Platform.isAndroid ? "http://10.0.2.2:8000" : "http://127.0.0.1:8000";
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
              const Text(
                "Inscrivez-vous pour voir votre profil",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AuthScreen()),
                    );
                  },
                  child: const Text("S'inscrire / Se connecter", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
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
            style: const TextStyle(
              color: Colors.white,
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
                      color: _profileTabIndex == 0 ? Colors.white : Colors.white12,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Publications',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _profileTabIndex == 0 ? Colors.black : Colors.white,
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
                      color: _profileTabIndex == 1 ? Colors.white : Colors.white12,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Explorer',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _profileTabIndex == 1 ? Colors.black : Colors.white,
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
                backgroundColor: Colors.white,
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF121B2D),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.videocam_outlined, color: Color(0xFF7C9BFF), size: 34),
            ),
            const SizedBox(height: 18),
            const Text("Aucune vidéo disponible.", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text("Publiez une première vidéo pour alimenter votre fil.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C9BFF)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const UploadScreen()),
                ).then((_) => _fetchVideos());
              },
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text("Publier une vidéo", style: TextStyle(color: Colors.white)),
            )
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
        scaffoldBackgroundColor: const Color(0xFF0B1A2E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B1020),
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
          separatorBuilder: (_, _) => const Divider(color: Colors.white12, height: 1),
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
          subtitle: Text('Appuyez pour ouvrir', style: const TextStyle(color: Colors.white60)),
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