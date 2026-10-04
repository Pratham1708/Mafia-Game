// Holds the current player's private role — read only by the owning player.
//
// Firestore path: rooms/{roomId}/privatePlayerData/{uid}
// Firestore rule:  allow read: if isOwner(uid);  write: if false;
import 'player_role.dart';

class PrivatePlayerData {
  final PlayerRole role;
  final bool hasUsedAbility;

  const PrivatePlayerData({
    required this.role,
    this.hasUsedAbility = false,
  });

  factory PrivatePlayerData.fromMap(Map<String, dynamic> data) {
    return PrivatePlayerData(
      role: PlayerRole.fromString(data['role'] as String?),
      hasUsedAbility: (data['hasUsedAbility'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'role': role.name,
        'hasUsedAbility': hasUsedAbility,
      };

  PrivatePlayerData copyWith({
    PlayerRole? role,
    bool? hasUsedAbility,
  }) {
    return PrivatePlayerData(
      role: role ?? this.role,
      hasUsedAbility: hasUsedAbility ?? this.hasUsedAbility,
    );
  }
}

