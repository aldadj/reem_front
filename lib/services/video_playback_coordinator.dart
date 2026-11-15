import 'dart:async';

import 'package:flutter/foundation.dart';

/// Garantit qu'une seule vidéo joue à la fois.
///
/// Ancienne version : toutes les opérations passaient par une file unique
/// ("_pendingOperation"). Si UNE seule pause ne se terminait jamais (lecteur
/// encore en ouverture, lecteur détruit...), toute la file restait bloquée et
/// plus aucune vidéo ne démarrait. Ici les pauses ne bloquent plus la lecture.
class VideoPlaybackCoordinator {
  VideoPlaybackCoordinator._();

  static final Map<Object, Future<void> Function()> _pausePlayers = {};
  static Object? _activePlayer;

  static void register(Object id, Future<void> Function() pause) {
    _pausePlayers[id] = pause;
  }

  static void unregister(Object id) {
    _pausePlayers.remove(id);
    if (identical(_activePlayer, id)) _activePlayer = null;
  }

  static Future<void> activate(Object id, Future<void> Function() play) async {
    _activePlayer = id;

    // On met les autres en pause sans attendre leur réponse.
    for (final entry in _pausePlayers.entries.toList()) {
      if (identical(entry.key, id)) continue;
      unawaited(_safe(entry.value));
    }

    try {
      await play().timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[Reem autoplay] play() a échoué : $e');
    }
  }

  static Future<void> deactivate(Object id) async {
    if (!identical(_activePlayer, id)) return;
    await _safe(() async => _pausePlayers[id]?.call());
    if (identical(_activePlayer, id)) _activePlayer = null;
  }

  static Future<void> _safe(Future<void>? Function() action) async {
    try {
      await action()?.timeout(const Duration(seconds: 2));
    } catch (_) {}
  }
}
