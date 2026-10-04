import 'package:cloud_firestore/cloud_firestore.dart';
import 'player_role.dart';

/// Public player document.
///
/// Firestore path: rooms/{roomId}/players/{uid}
/// Readable by all room members — contains NO secret game data.
///
/// [role] is kept in the Dart model for two safe purposes only:
///   1. After GAME_OVER: the server writes each player's role to this document
///      so the final role-reveal screen can show all roles.
///   2. In LocalSimulationGameService: in-memory simulation stores roles here.
///
/// During PLAYING, [role] is PlayerRole.unknown for every player except
/// the current player who reads their own role from privatePlayerData/{uid}.
class Player {
  final String uid;
  final String name;

  /// During the game this is [PlayerRole.unknown] for all other players.
  /// After GAME_OVER the server writes the real role here for the reveal screen.
  /// For the local simulation service roles are stored here in-memory only.
  final PlayerRole role;

  final bool isAlive;
  final bool isHost;
  final bool isBot;
  final DateTime joinedAt;

  const Player({
    required this.uid,
    required this.name,
    this.role = PlayerRole.unknown,
    this.isAlive = true,
    this.isHost = false,
    this.isBot = false,
    required this.joinedAt,
  });

  Player copyWith({
    String? uid,
    String? name,
    PlayerRole? role,
    bool? isAlive,
    bool? isHost,
    bool? isBot,
    DateTime? joinedAt,
  }) {
    return Player(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      role: role ?? this.role,
      isAlive: isAlive ?? this.isAlive,
      isHost: isHost ?? this.isHost,
      isBot: isBot ?? this.isBot,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  /// Public Firestore document — does NOT include [role].
  /// Role is written to privatePlayerData/{uid} instead.
  /// Exception: after GAME_OVER the server writes role here for the reveal.
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      // role intentionally omitted — stored in privatePlayerData/{uid}
      'isAlive': isAlive,
      'isHost': isHost,
      'isBot': isBot,
      'joinedAt': Timestamp.fromDate(joinedAt),
    };
  }

  factory Player.fromMap(Map<String, dynamic> data, String id) {
    DateTime parsedJoinedAt = DateTime.now();
    if (data['joinedAt'] is Timestamp) {
      parsedJoinedAt = (data['joinedAt'] as Timestamp).toDate();
    } else if (data['joinedAt'] is String) {
      parsedJoinedAt = DateTime.tryParse(data['joinedAt'] as String) ?? DateTime.now();
    }

    return Player(
      uid: (data['uid'] as String?) ?? id,
      name: (data['name'] as String?) ?? 'Player',
      // role defaults to unknown; populated only at GAME_OVER reveal or in local sim
      role: PlayerRole.fromString(data['role'] as String?),
      isAlive: (data['isAlive'] as bool?) ?? true,
      isHost: (data['isHost'] as bool?) ?? false,
      isBot: (data['isBot'] as bool?) ?? false,
      joinedAt: parsedJoinedAt,
    );
  }
}
