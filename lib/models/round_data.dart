/// Public round document — contains ONLY information legitimately visible to all players.
///
/// Firestore path: rooms/{roomId}/rounds/{roundNumber}
/// Readable by all room members.
///
/// Private data lives in subcollections:
///   privateActions/{uid}   — individual secret action (owner-read only)
///   privateVotes/{uid}     — individual vote (owner-read only)
///   privateResults/{uid}   — Detective investigation result (owner-read only)
///
/// Removed from this document (compared to Phase 1):
///   - actions map (was: uid → {targetId, role})
///   - votes map (was: uid → {targetId})
///   - investigationResults map
///   - mafiaTarget
///   - doctorTarget
class RoundData {
  final int roundNumber;

  /// How many secret actions have been submitted (count only — no details).
  final int actionsCount;

  /// How many votes have been cast (count only — no details).
  final int votesCount;

  /// UID of the player eliminated during the secret actions phase.
  /// Null if no one was eliminated (Doctor protected successfully).
  final String? eliminatedInActions;

  /// UIDs of ALL players eliminated during secret actions.
  final List<String> eliminatedPlayerIds;

  /// UID of the player eliminated by vote.
  final String? eliminatedInVote;

  final bool actionsResolved;
  final bool votesResolved;

  /// UIDs of players who have cast a vote this round (contains no target info).
  final List<String> votedUids;

  /// Aggregate vote counts per candidate (targetUid -> count).
  final Map<String, int> voteTally;

  const RoundData({
    required this.roundNumber,
    this.actionsCount = 0,
    this.votesCount = 0,
    this.eliminatedInActions,
    this.eliminatedPlayerIds = const [],
    this.eliminatedInVote,
    this.actionsResolved = false,
    this.votesResolved = false,
    this.votedUids = const [],
    this.voteTally = const {},
  });

  RoundData copyWith({
    int? roundNumber,
    int? actionsCount,
    int? votesCount,
    String? eliminatedInActions,
    List<String>? eliminatedPlayerIds,
    String? eliminatedInVote,
    bool? actionsResolved,
    bool? votesResolved,
    List<String>? votedUids,
    Map<String, int>? voteTally,
  }) {
    return RoundData(
      roundNumber: roundNumber ?? this.roundNumber,
      actionsCount: actionsCount ?? this.actionsCount,
      votesCount: votesCount ?? this.votesCount,
      eliminatedInActions: eliminatedInActions ?? this.eliminatedInActions,
      eliminatedPlayerIds: eliminatedPlayerIds ?? this.eliminatedPlayerIds,
      eliminatedInVote: eliminatedInVote ?? this.eliminatedInVote,
      actionsResolved: actionsResolved ?? this.actionsResolved,
      votesResolved: votesResolved ?? this.votesResolved,
      votedUids: votedUids ?? this.votedUids,
      voteTally: voteTally ?? this.voteTally,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'roundNumber': roundNumber,
      'actionsCount': actionsCount,
      'votesCount': votesCount,
      'eliminatedInActions': eliminatedInActions,
      'eliminatedPlayerIds': eliminatedPlayerIds,
      'eliminatedInVote': eliminatedInVote,
      'actionsResolved': actionsResolved,
      'votesResolved': votesResolved,
      'votedUids': votedUids,
      'voteTally': voteTally,
    };
  }

  factory RoundData.fromMap(Map<String, dynamic> data, [int? roundNum]) {
    final rawElimIds = data['eliminatedPlayerIds'];
    List<String> parsedElimIds = [];
    if (rawElimIds is List) {
      parsedElimIds = rawElimIds.map((e) => e.toString()).toList();
    } else if (data['eliminatedInActions'] != null) {
      parsedElimIds = [data['eliminatedInActions'] as String];
    }

    final rawVotedUids = data['votedUids'];
    List<String> parsedVotedUids = [];
    if (rawVotedUids is List) {
      parsedVotedUids = rawVotedUids.map((e) => e.toString()).toList();
    }

    final rawTally = data['voteTally'];
    Map<String, int> parsedTally = {};
    if (rawTally is Map) {
      rawTally.forEach((k, v) {
        if (v is num) parsedTally[k.toString()] = v.toInt();
      });
    }

    return RoundData(
      roundNumber: (data['roundNumber'] as num?)?.toInt() ?? (roundNum ?? 1),
      actionsCount: (data['actionsCount'] as num?)?.toInt() ?? 0,
      votesCount: (data['votesCount'] as num?)?.toInt() ?? 0,
      eliminatedInActions: data['eliminatedInActions'] as String?,
      eliminatedPlayerIds: parsedElimIds,
      eliminatedInVote: data['eliminatedInVote'] as String?,
      actionsResolved: (data['actionsResolved'] as bool?) ?? false,
      votesResolved: (data['votesResolved'] as bool?) ?? false,
      votedUids: parsedVotedUids,
      voteTally: parsedTally,
    );
  }
}
