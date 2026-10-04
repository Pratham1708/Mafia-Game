/// The roles in Mafia multiplayer.
enum PlayerRole {
  mafia,
  detective,
  doctor,
  bodyguard,
  vigilante,
  civilian,
  unknown;

  static PlayerRole fromString(String? role) {
    if (role == null) return PlayerRole.unknown;
    return PlayerRole.values.firstWhere(
      (e) => e.name.toLowerCase() == role.toLowerCase(),
      orElse: () => PlayerRole.unknown,
    );
  }

  String get displayName {
    switch (this) {
      case PlayerRole.mafia:
        return 'Mafia';
      case PlayerRole.detective:
        return 'Detective';
      case PlayerRole.doctor:
        return 'Doctor';
      case PlayerRole.bodyguard:
        return 'Bodyguard';
      case PlayerRole.vigilante:
        return 'Vigilante';
      case PlayerRole.civilian:
        return 'Civilian';
      case PlayerRole.unknown:
        return 'Unknown';
    }
  }

  String get iconEmoji {
    switch (this) {
      case PlayerRole.mafia:
        return '🔪';
      case PlayerRole.detective:
        return '🕵️';
      case PlayerRole.doctor:
        return '🩺';
      case PlayerRole.bodyguard:
        return '🛡️';
      case PlayerRole.vigilante:
        return '🎯';
      case PlayerRole.civilian:
        return '👤';
      case PlayerRole.unknown:
        return '❓';
    }
  }

  String get teamDisplayName {
    switch (this) {
      case PlayerRole.mafia:
        return 'MAFIA TEAM';
      case PlayerRole.detective:
      case PlayerRole.doctor:
      case PlayerRole.bodyguard:
      case PlayerRole.vigilante:
      case PlayerRole.civilian:
        return 'CIVILIAN TEAM';
      case PlayerRole.unknown:
        return 'UNKNOWN';
    }
  }

  String get description {
    switch (this) {
      case PlayerRole.mafia:
        return 'You are part of the Mafia. Secretly choose a player to eliminate.';
      case PlayerRole.detective:
        return 'Find the Mafia. Secretly investigate one player each round.';
      case PlayerRole.doctor:
        return 'Protect a player. Shield someone each round from attacks.';
      case PlayerRole.bodyguard:
        return 'You protect another player. If Mafia attacks the player you protect, you intercept the attack and are eliminated instead. The protected player survives.';
      case PlayerRole.vigilante:
        return 'Town vigilante. You have ONE secret elimination shot for the entire game.';
      case PlayerRole.civilian:
        return 'Find the Mafia through discussion and voting.';
      case PlayerRole.unknown:
        return 'Role unassigned.';
    }
  }

  String get objective {
    switch (this) {
      case PlayerRole.mafia:
        return 'Eliminate civilians until the Mafia reaches parity.';
      case PlayerRole.detective:
        return 'Find the Mafia before they outnumber the town.';
      case PlayerRole.doctor:
        return 'Keep town members alive through nocturnal protection.';
      case PlayerRole.bodyguard:
        return 'Shield vital town members. If they are targeted, you sacrifice yourself to save them.';
      case PlayerRole.vigilante:
        return 'Take out a Mafia member with your single bullet.';
      case PlayerRole.civilian:
        return 'Uncover and vote out the Mafia during discussion.';
      case PlayerRole.unknown:
        return 'Survive.';
    }
  }

  /// Whether this role performs a secret action during the actions phase.
  bool get hasSecretAction =>
      this == PlayerRole.mafia ||
      this == PlayerRole.detective ||
      this == PlayerRole.doctor ||
      this == PlayerRole.bodyguard ||
      this == PlayerRole.vigilante;
}
