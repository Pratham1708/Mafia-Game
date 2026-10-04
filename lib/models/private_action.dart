// Holds a single player's private secret action for one round.
//
// Firestore path: rooms/{roomId}/rounds/{N}/privateActions/{uid}
// Firestore rule:  allow read: if isOwner(uid);  write: if false;
import 'player_role.dart';

class PrivateAction {
  final String targetId;
  final PlayerRole role;

  const PrivateAction({required this.targetId, required this.role});

  factory PrivateAction.fromMap(Map<String, dynamic> data) {
    return PrivateAction(
      targetId: (data['targetId'] as String?) ?? '',
      role: PlayerRole.fromString(data['role'] as String?),
    );
  }

  Map<String, dynamic> toMap() => {
        'targetId': targetId,
        'role': role.name,
      };
}
