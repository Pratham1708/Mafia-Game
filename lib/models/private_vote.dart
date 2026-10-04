/// Holds a single player's private vote for one round.
///
/// Firestore path: rooms/{roomId}/rounds/{N}/privateVotes/{uid}
/// Firestore rule:  allow read: if isOwner(uid);  write: if false;
class PrivateVote {
  final String targetId;

  const PrivateVote({required this.targetId});

  factory PrivateVote.fromMap(Map<String, dynamic> data) {
    return PrivateVote(targetId: (data['targetId'] as String?) ?? '');
  }

  Map<String, dynamic> toMap() => {'targetId': targetId};
}
