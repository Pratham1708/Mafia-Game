/// Game phases following the round-based state machine.
/// Note: No "day" or "night" terminology is used.
enum GamePhase {
  lobby,
  roleReveal,
  actions,
  roundResult,
  discussion,
  voting,
  elimination,
  gameOver;

  static GamePhase fromString(String? phase) {
    if (phase == null) return GamePhase.lobby;
    return GamePhase.values.firstWhere(
      (e) => e.name.toLowerCase() == phase.toLowerCase(),
      orElse: () => GamePhase.lobby,
    );
  }

  String get displayName {
    switch (this) {
      case GamePhase.lobby:
        return 'Lobby';
      case GamePhase.roleReveal:
        return 'Role Reveal';
      case GamePhase.actions:
        return 'Secret Actions';
      case GamePhase.roundResult:
        return 'Round Result';
      case GamePhase.discussion:
        return 'Discussion';
      case GamePhase.voting:
        return 'Voting';
      case GamePhase.elimination:
        return 'Elimination';
      case GamePhase.gameOver:
        return 'Game Over';
    }
  }

  String get instruction {
    switch (this) {
      case GamePhase.lobby:
        return 'Waiting for players to join...';
      case GamePhase.roleReveal:
        return 'Memorize your role in secret.';
      case GamePhase.actions:
        return 'Perform your role secret action.';
      case GamePhase.roundResult:
        return 'Action resolution for this round.';
      case GamePhase.discussion:
        return 'Discuss and deduce who is Mafia.';
      case GamePhase.voting:
        return 'Vote for the player you suspect is Mafia.';
      case GamePhase.elimination:
        return 'A player has been eliminated.';
      case GamePhase.gameOver:
        return 'The game has ended.';
    }
  }
}
