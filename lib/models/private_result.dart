/// Holds the Detective's private investigation result for one round.
///
/// Firestore path: rooms/{roomId}/rounds/{N}/privateResults/{detectiveUid}
/// Firestore rule:  allow read: if isOwner(detectiveUid);  write: if false;
class PrivateResult {
  final String targetId;
  final bool isMafia;
  final bool bodyguardIntercepted;

  const PrivateResult({
    required this.targetId,
    required this.isMafia,
    this.bodyguardIntercepted = false,
  });

  factory PrivateResult.fromMap(Map<String, dynamic> data) {
    return PrivateResult(
      targetId: (data['targetId'] as String?) ?? '',
      isMafia: (data['isMafia'] as bool?) ?? false,
      bodyguardIntercepted: (data['bodyguardIntercepted'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'targetId': targetId,
        'isMafia': isMafia,
        'bodyguardIntercepted': bodyguardIntercepted,
      };
}
