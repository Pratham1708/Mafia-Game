import 'package:cloud_firestore/cloud_firestore.dart';
import 'game_phase.dart';

enum RoomStatus {
  lobby,
  playing,
  gameOver;

  static RoomStatus fromString(String? status) {
    if (status == null) return RoomStatus.lobby;
    final normalized = status.replaceAll('_', '').toLowerCase();
    return RoomStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == normalized,
      orElse: () => RoomStatus.lobby,
    );
  }
}

class Room {
  final String id;
  final String code;
  final String hostId;
  final RoomStatus status;
  final int currentRound;
  final GamePhase currentPhase;
  final DateTime createdAt;
  final int maxPlayers;
  final String? winner; // 'MAFIA' or 'CIVILIANS'
  final String? eliminatedThisRound; // uid eliminated in secret action
  final String? votedOutThisRound; // uid eliminated in vote
  final String? publicMessage;
  final DateTime? discussionEndTimestamp;
  final int discussionDurationSeconds;
  final DateTime? votingEndTimestamp;
  final int votingDurationSeconds;
  final DateTime? actionsEndTimestamp;
  final int actionsDurationSeconds;

  const Room({
    required this.id,
    required this.code,
    required this.hostId,
    this.status = RoomStatus.lobby,
    this.currentRound = 0,
    this.currentPhase = GamePhase.lobby,
    required this.createdAt,
    this.maxPlayers = 12,
    this.winner,
    this.eliminatedThisRound,
    this.votedOutThisRound,
    this.publicMessage,
    this.discussionEndTimestamp,
    this.discussionDurationSeconds = 60,
    this.votingEndTimestamp,
    this.votingDurationSeconds = 45,
    this.actionsEndTimestamp,
    this.actionsDurationSeconds = 45,
  });

  Room copyWith({
    String? id,
    String? code,
    String? hostId,
    RoomStatus? status,
    int? currentRound,
    GamePhase? currentPhase,
    DateTime? createdAt,
    int? maxPlayers,
    String? winner,
    String? eliminatedThisRound,
    String? votedOutThisRound,
    String? publicMessage,
    DateTime? discussionEndTimestamp,
    int? discussionDurationSeconds,
    DateTime? votingEndTimestamp,
    int? votingDurationSeconds,
    DateTime? actionsEndTimestamp,
    int? actionsDurationSeconds,
  }) {
    return Room(
      id: id ?? this.id,
      code: code ?? this.code,
      hostId: hostId ?? this.hostId,
      status: status ?? this.status,
      currentRound: currentRound ?? this.currentRound,
      currentPhase: currentPhase ?? this.currentPhase,
      createdAt: createdAt ?? this.createdAt,
      maxPlayers: maxPlayers ?? this.maxPlayers,
      winner: winner ?? this.winner,
      eliminatedThisRound: eliminatedThisRound ?? this.eliminatedThisRound,
      votedOutThisRound: votedOutThisRound ?? this.votedOutThisRound,
      publicMessage: publicMessage ?? this.publicMessage,
      discussionEndTimestamp: discussionEndTimestamp ?? this.discussionEndTimestamp,
      discussionDurationSeconds: discussionDurationSeconds ?? this.discussionDurationSeconds,
      votingEndTimestamp: votingEndTimestamp ?? this.votingEndTimestamp,
      votingDurationSeconds: votingDurationSeconds ?? this.votingDurationSeconds,
      actionsEndTimestamp: actionsEndTimestamp ?? this.actionsEndTimestamp,
      actionsDurationSeconds: actionsDurationSeconds ?? this.actionsDurationSeconds,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'roomId': id,
      'roomCode': code,
      'hostId': hostId,
      'status': status == RoomStatus.gameOver ? 'GAME_OVER' : status.name.toUpperCase(),
      'currentRound': currentRound,
      'currentPhase': currentPhase.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'maxPlayers': maxPlayers,
      'winner': winner,
      'eliminatedThisRound': eliminatedThisRound,
      'votedOutThisRound': votedOutThisRound,
      'publicMessage': publicMessage,
      'discussionEndTimestamp': discussionEndTimestamp != null
          ? Timestamp.fromDate(discussionEndTimestamp!)
          : null,
      'discussionDurationSeconds': discussionDurationSeconds,
      'votingEndTimestamp': votingEndTimestamp != null
          ? Timestamp.fromDate(votingEndTimestamp!)
          : null,
      'votingDurationSeconds': votingDurationSeconds,
      'actionsEndTimestamp': actionsEndTimestamp != null
          ? Timestamp.fromDate(actionsEndTimestamp!)
          : null,
      'actionsDurationSeconds': actionsDurationSeconds,
    };
  }

  factory Room.fromMap(Map<String, dynamic> data, String id) {
    DateTime parsedCreatedAt = DateTime.now();
    if (data['createdAt'] is Timestamp) {
      parsedCreatedAt = (data['createdAt'] as Timestamp).toDate();
    } else if (data['createdAt'] is String) {
      parsedCreatedAt = DateTime.tryParse(data['createdAt'] as String) ?? DateTime.now();
    }

    DateTime? parsedDiscussionEnd;
    if (data['discussionEndTimestamp'] is Timestamp) {
      parsedDiscussionEnd = (data['discussionEndTimestamp'] as Timestamp).toDate();
    } else if (data['discussionEndTimestamp'] is String) {
      parsedDiscussionEnd = DateTime.tryParse(data['discussionEndTimestamp'] as String);
    }

    DateTime? parsedVotingEnd;
    if (data['votingEndTimestamp'] is Timestamp) {
      parsedVotingEnd = (data['votingEndTimestamp'] as Timestamp).toDate();
    } else if (data['votingEndTimestamp'] is String) {
      parsedVotingEnd = DateTime.tryParse(data['votingEndTimestamp'] as String);
    }

    DateTime? parsedActionsEnd;
    if (data['actionsEndTimestamp'] is Timestamp) {
      parsedActionsEnd = (data['actionsEndTimestamp'] as Timestamp).toDate();
    } else if (data['actionsEndTimestamp'] is String) {
      parsedActionsEnd = DateTime.tryParse(data['actionsEndTimestamp'] as String);
    }

    return Room(
      id: (data['roomId'] as String?) ?? id,
      code: (data['roomCode'] as String?) ?? '',
      hostId: (data['hostId'] as String?) ?? '',
      status: RoomStatus.fromString(data['status'] as String?),
      currentRound: (data['currentRound'] as num?)?.toInt() ?? 0,
      currentPhase: GamePhase.fromString(data['currentPhase'] as String?),
      createdAt: parsedCreatedAt,
      maxPlayers: (data['maxPlayers'] as num?)?.toInt() ?? 12,
      winner: data['winner'] as String?,
      eliminatedThisRound: data['eliminatedThisRound'] as String?,
      votedOutThisRound: data['votedOutThisRound'] as String?,
      publicMessage: data['publicMessage'] as String?,
      discussionEndTimestamp: parsedDiscussionEnd,
      discussionDurationSeconds: (data['discussionDurationSeconds'] as num?)?.toInt() ?? 60,
      votingEndTimestamp: parsedVotingEnd,
      votingDurationSeconds: (data['votingDurationSeconds'] as num?)?.toInt() ?? 45,
      actionsEndTimestamp: parsedActionsEnd,
      actionsDurationSeconds: (data['actionsDurationSeconds'] as num?)?.toInt() ?? 45,
    );
  }
}
