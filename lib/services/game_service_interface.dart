import '../models/chat_message.dart';
import '../models/player.dart';
import '../models/player_role.dart';
import '../models/private_action.dart';
import '../models/private_player_data.dart';
import '../models/private_result.dart';
import '../models/private_vote.dart';
import '../models/room.dart';
import '../models/round_data.dart';

abstract class IGameService {
  // ─── Room lifecycle ─────────────────────────────────────────────────────────

  /// Creates a new room in LOBBY status with generated code.
  Future<Room> createRoom({required String hostName});

  /// Joins an existing room in LOBBY status.
  Future<Room> joinRoom({required String roomCode, required String playerName});

  /// Leaves a room (deletes own player doc; host leaving in LOBBY deletes room).
  Future<void> leaveRoom({required String roomId, required String uid});

  /// Claims host privileges if the current host disconnected or disappeared.
  /// Server validates caller is an active, living player in the room.
  Future<void> claimHost(String roomId);

  // ─── Public real-time streams ───────────────────────────────────────────────

  /// Real-time stream of the public Room document.
  Stream<Room> streamRoom(String roomId);

  /// Real-time stream of the PUBLIC player list (roles are PlayerRole.unknown
  /// during PLAYING; real roles appear only after GAME_OVER reveal).
  Stream<List<Player>> streamPlayers(String roomId);

  /// Real-time stream of the PUBLIC round document (counts only, no private data).
  Stream<RoundData> streamRound(String roomId, int roundNumber);

  /// Real-time stream of living discussion text messages.
  /// Only living players receive these messages.
  Stream<List<ChatMessage>> streamMessages(String roomId);

  /// Real-time stream of spectator messages.
  /// Only dead players receive these messages.
  Stream<List<ChatMessage>> streamSpectatorMessages(String roomId);

  // ─── Private data streams (owner-read only) ─────────────────────────────────

  /// Stream of the current player's own secret role.
  /// Reads from: rooms/{roomId}/privatePlayerData/{myUid}
  Stream<PlayerRole> streamMyRole(String roomId);

  /// Stream of the current player's own private player data (role, hasUsedAbility).
  Stream<PrivatePlayerData?> streamMyPlayerData(String roomId);

  /// Stream of the current player's own submitted secret action for a round.
  /// Returns null if the player has not yet submitted.
  /// Reads from: rooms/{roomId}/rounds/{roundNumber}/privateActions/{myUid}
  Stream<PrivateAction?> streamMyAction(String roomId, int roundNumber);

  /// Stream of the Detective's own investigation result for a round.
  /// Returns null for non-Detectives or before resolution.
  /// Reads from: rooms/{roomId}/rounds/{roundNumber}/privateResults/{myUid}
  Stream<PrivateResult?> streamMyResult(String roomId, int roundNumber);

  /// Stream of the current player's own submitted vote for a round.
  /// Returns null if the player has not yet voted.
  /// Reads from: rooms/{roomId}/rounds/{roundNumber}/privateVotes/{myUid}
  Stream<PrivateVote?> streamMyVote(String roomId, int roundNumber);

  // ─── Server-authoritative game actions ─────────────────────────────────────

  /// Starts the game: server assigns roles, transitions to roleReveal phase.
  Future<void> startGame(String roomId);

  /// Advances from roleReveal to actions phase.
  Future<void> advanceToActions(String roomId);

  /// Submits the current player's secret action during the actions phase.
  /// [role] is still passed for the local simulation service; the Firebase
  /// implementation ignores it — the server reads the role from Firestore.
  Future<void> submitAction({
    required String roomId,
    required int roundNumber,
    required String uid,
    required String targetId,
    required PlayerRole role,
  });

  /// Advances from roundResult to discussion phase.
  Future<void> advanceToDiscussion(String roomId);

  /// Sends a real-time message during the discussion phase.
  /// Validated server-side (only living room members).
  Future<void> sendMessage({required String roomId, required String message});

  /// Sends a spectator message.
  /// Validated server-side (only eliminated room members).
  Future<void> sendSpectatorMessage({required String roomId, required String message});

  /// Advances from discussion (or roundResult) to voting phase.
  Future<void> advanceToVoting(String roomId);

  /// Submits the current player's vote during the voting phase.
  Future<void> submitVote({
    required String roomId,
    required int roundNumber,
    required String uid,
    required String targetId,
  });

  /// Advances from elimination to next round or ends the game.
  Future<void> advanceToNextRoundOrEnd(String roomId);

  /// Forces resolution of votes when the voting timer expires (abstained players cast no vote).
  Future<void> resolveVotesOnTimeout(String roomId, int roundNumber);

  /// Forces resolution of actions when the actions timer expires (unsubmitted actions are skipped).
  Future<void> resolveActionsOnTimeout(String roomId, int roundNumber);

  /// Adds a mock/test player (bot) to the lobby.
  Future<void> addTestPlayer({required String roomId, required String name});

  /// Resets a finished game (GAME_OVER) back to LOBBY status so all players
  /// in the room can play again without creating a new room code.
  Future<void> resetRoomForNewGame(String roomId);
}
