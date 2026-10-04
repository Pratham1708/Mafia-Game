import 'package:flutter/material.dart';
import '../../models/game_phase.dart';
import '../../models/player.dart';
import '../../models/player_role.dart';
import '../../models/private_action.dart';
import '../../models/private_player_data.dart';
import '../../models/private_result.dart';
import '../../models/private_vote.dart';
import '../../models/room.dart';
import '../../models/round_data.dart';
import '../../services/auth_service.dart';
import '../../services/game_service_provider.dart';
import '../../widgets/error_view.dart';
import '../../widgets/game_phase_indicator.dart';
import '../../widgets/loading_view.dart';
import 'actions_phase_view.dart';
import 'discussion_view.dart';
import 'elimination_view.dart';
import 'game_over_view.dart';
import 'role_reveal_view.dart';
import 'round_result_view.dart';
import 'voting_phase_view.dart';
import '../lobby_screen.dart';

class GameScreen extends StatelessWidget {
  final String roomId;
  final String roomCode;

  const GameScreen({
    super.key,
    required this.roomId,
    required this.roomCode,
  });

  @override
  Widget build(BuildContext context) {
    final service = GameServiceProvider.instance.current;
    final currentUid = AuthService.instance.currentUid;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave Game?'),
            content: const Text('Are you sure you want to abandon the match?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('STAY'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('LEAVE'),
              ),
            ],
          ),
        );
        if (shouldExit == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'MAFIA • $roomCode',
            style: const TextStyle(letterSpacing: 2.0, fontSize: 18),
          ),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: StreamBuilder<Room>(
            stream: service.streamRoom(roomId),
            builder: (context, roomSnap) {
              if (roomSnap.hasError) {
                return ErrorView(
                  title: 'Room Unavailable',
                  message: roomSnap.error.toString(),
                  onRetry: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  retryLabel: 'RETURN HOME',
                );
              }
              if (!roomSnap.hasData) {
                return const LoadingView(message: 'Synchronizing game state...');
              }

              final room = roomSnap.data!;
              debugPrint(
                  'ROOM LISTENER UPDATE (GameScreen): roomId=$roomId, status=${room.status.name}, currentPhase=${room.currentPhase.name}, currentRound=${room.currentRound}');

              // If the game was reset to lobby (e.g. from PLAY AGAIN), navigate all players back to LobbyScreen!
              if (room.status == RoomStatus.lobby || room.currentPhase == GamePhase.lobby) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => LobbyScreen(
                          roomId: roomId,
                          roomCode: roomCode,
                          isHost: room.hostId == currentUid,
                        ),
                      ),
                    );
                  }
                });
                return const Scaffold(
                  body: LoadingView(message: 'Returning to lobby...'),
                );
              }

              final currentRoundNum = room.currentRound > 0 ? room.currentRound : 1;

              return StreamBuilder<List<Player>>(
                stream: service.streamPlayers(roomId),
                builder: (context, playersSnap) {
                  if (playersSnap.hasError) {
                    return ErrorView(
                      title: 'Player Sync Error',
                      message: playersSnap.error.toString(),
                    );
                  }
                  if (!playersSnap.hasData) {
                    return const LoadingView(message: 'Synchronizing players...');
                  }

                  final players = playersSnap.data!;
                  final currentPlayer = players.cast<Player?>().firstWhere(
                        (p) => p?.uid == currentUid,
                        orElse: () => Player(
                          uid: currentUid ?? 'unknown',
                          name: AuthService.instance.displayName ?? 'Player',
                          joinedAt: DateTime.now(),
                        ),
                      )!;

                  final livingCount = players.where((p) => p.isAlive).length;
                  final isHost = currentPlayer.isHost;

                  // ── Private role stream (this player only) ──────────────
                  return StreamBuilder<PlayerRole>(
                    stream: service.streamMyRole(roomId),
                    builder: (context, roleSnap) {
                      // Use streamed private role; fall back to unknown while loading
                      final myRole = roleSnap.data ?? PlayerRole.unknown;

                      // ── Public round data stream ────────────────────────
                      return StreamBuilder<RoundData>(
                        stream: service.streamRound(roomId, currentRoundNum),
                        builder: (context, roundSnap) {
                          final roundData = roundSnap.data ?? RoundData(roundNumber: currentRoundNum);

                          return Column(
                            children: [
                              if (room.currentPhase != GamePhase.gameOver) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20.0,
                                    vertical: 6.0,
                                  ),
                                  child: GamePhaseIndicator(
                                    round: room.currentRound,
                                    phase: room.currentPhase,
                                    livingCount: livingCount,
                                  ),
                                ),
                              ],
                              Expanded(
                                child: _buildPhaseContent(
                                  context: context,
                                  room: room,
                                  players: players,
                                  currentPlayer: currentPlayer,
                                  myRole: myRole,
                                  roundData: roundData,
                                  isHost: isHost,
                                  service: service,
                                  currentRoundNum: currentRoundNum,
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPhaseContent({
    required BuildContext context,
    required Room room,
    required List<Player> players,
    required Player currentPlayer,
    required PlayerRole myRole,
    required RoundData roundData,
    required bool isHost,
    required dynamic service,
    required int currentRoundNum,
  }) {
    switch (room.currentPhase) {
      case GamePhase.roleReveal:
        return RoleRevealView(
          roomId: room.id,
          currentPlayer: currentPlayer,
          myRole: myRole,
          isHost: isHost,
        );

      case GamePhase.actions:
        // Stream of player's own private action & player data (to know if they already submitted / used ability)
        return StreamBuilder<PrivatePlayerData?>(
          stream: service.streamMyPlayerData(roomId),
          builder: (context, playerDataSnap) {
            return StreamBuilder<PrivateAction?>(
              stream: service.streamMyAction(roomId, currentRoundNum),
              builder: (context, actionSnap) {
                return ActionsPhaseView(
                  roomId: room.id,
                  roundNumber: room.currentRound,
                  currentPlayer: currentPlayer,
                  myRole: myRole,
                  allPlayers: players,
                  roundData: roundData,
                  myAction: actionSnap.data,
                  hasUsedAbility: playerDataSnap.data?.hasUsedAbility ?? false,
                );
              },
            );
          },
        );

      case GamePhase.roundResult:
        // Detective streams their own private investigation result
        return StreamBuilder<PrivateResult?>(
          stream: service.streamMyResult(roomId, currentRoundNum),
          builder: (context, resultSnap) {
            return RoundResultView(
              room: room,
              currentPlayer: currentPlayer,
              myRole: myRole,
              allPlayers: players,
              roundData: roundData,
              myResult: resultSnap.data,
              isHost: isHost,
            );
          },
        );

      case GamePhase.discussion:
        return DiscussionView(
          roomId: room.id,
          room: room,
          currentPlayer: currentPlayer,
          players: players,
          isHost: isHost,
        );

      case GamePhase.voting:
        // Stream of player's own private vote (to know if they already voted)
        return StreamBuilder<PrivateVote?>(
          stream: service.streamMyVote(roomId, currentRoundNum),
          builder: (context, voteSnap) {
            return VotingPhaseView(
              roomId: room.id,
              room: room,
              roundNumber: room.currentRound,
              currentPlayer: currentPlayer,
              allPlayers: players,
              roundData: roundData,
              myVote: voteSnap.data,
              isHost: isHost,
            );
          },
        );

      case GamePhase.elimination:
        return EliminationView(
          room: room,
          allPlayers: players,
          roundData: roundData,
          isHost: isHost,
        );

      case GamePhase.gameOver:
        // At GAME_OVER the server has written real roles to public player docs
        return GameOverView(
          room: room,
          allPlayers: players,
          isHost: isHost,
        );

      case GamePhase.lobby:
        // Transitioning back to lobby after Play Again
        return const LoadingView(message: 'Returning to lobby...');
    }
  }
}
