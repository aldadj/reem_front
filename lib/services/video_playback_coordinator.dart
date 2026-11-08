import 'dart:async';

class VideoPlaybackCoordinator {
  VideoPlaybackCoordinator._();

  static final Map<Object, Future<void> Function()> _pausePlayers = {};
  static Future<void> _pendingOperation = Future<void>.value();
  static Object? _activePlayer;

  static void register(Object id, Future<void> Function() pause) {
    _pausePlayers[id] = pause;
  }

  static void unregister(Object id) {
    _pausePlayers.remove(id);
    if (identical(_activePlayer, id)) _activePlayer = null;
  }

  static Future<void> activate(Object id, Future<void> Function() play) {
    final operation = _pendingOperation.catchError((_) {}).then((_) async {
      for (final entry in _pausePlayers.entries.toList()) {
        if (!identical(entry.key, id)) await entry.value();
      }
      _activePlayer = id;
      await play();
    });
    _pendingOperation = operation;
    return operation;
  }

  static Future<void> deactivate(Object id) async {
    if (!identical(_activePlayer, id)) return;
    await _pausePlayers[id]?.call();
    if (identical(_activePlayer, id)) _activePlayer = null;
  }
}
