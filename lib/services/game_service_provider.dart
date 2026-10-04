import 'package:flutter/foundation.dart';
import 'firebase_game_service.dart';
import 'game_service_interface.dart';

/// Provides the active game service for the application.
///
/// In production, this always resolves to [FirebaseGameService] (online room multiplayer).
/// Test suites can inject an [IGameService] implementation via [setServiceForTesting].
class GameServiceProvider {
  static final GameServiceProvider instance = GameServiceProvider._internal();
  GameServiceProvider._internal();

  IGameService? _firebaseService;
  IGameService? _testService;

  /// Returns the authoritative game service.
  IGameService get current =>
      _testService ?? (_firebaseService ??= FirebaseGameService());

  /// Injects a service implementation for automated testing.
  @visibleForTesting
  void setServiceForTesting(IGameService? service) {
    _testService = service;
  }
}

