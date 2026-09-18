class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  
  String? _authToken;
  Map<String, dynamic>? _currentUser;
  
  // Fichier de stockage simplifié sans SharedPreferences pour commencer
  factory SessionManager() {
    return _instance;
  }
  
  SessionManager._internal();
  
  // Getters
  String? get authToken => _authToken;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isAuthenticated => _authToken != null;
  
  // Setters
  void setSession(String token, Map<String, dynamic> user) {
    _authToken = token;
    _currentUser = user;
  }
  
  void clearSession() {
    _authToken = null;
    _currentUser = null;
  }
  
  void setUser(Map<String, dynamic> user) {
    _currentUser = user;
  }
}
