import 'dart:async';
import 'package:flutter/material.dart';
import '../models/game_config.dart';
import '../models/player.dart';
import '../models/room.dart';
import '../services/auth_service.dart';
import '../services/game_service_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/loading_view.dart';
import '../widgets/player_card.dart';
import '../widgets/primary_button.dart';
import '../widgets/room_code_display.dart';
import 'game/game_screen.dart';

class LobbyScreen extends StatefulWidget {
  final String roomId;
  final String roomCode;
  final bool isHost;

  const LobbyScreen({
    super.key,
    required this.roomId,
    required this.roomCode,
    required this.isHost,
  });

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  StreamSubscription<Room>? _roomSubscription;
  bool _isStarting = false;
  bool _isAddingBot = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _listenToRoom();
  }

  void _listenToRoom() {
    final service = GameServiceProvider.instance.current;
    _roomSubscription = service.streamRoom(widget.roomId).listen(
      (room) {
        if (!mounted) return;
        debugPrint(
            'ROOM LISTENER UPDATE: status=${room.status.name}, currentPhase=${room.currentPhase.name}, currentRound=${room.currentRound}, roomId=${widget.roomId}');
        if (room.status == RoomStatus.playing) {
          // Transition everyone in the lobby to GameScreen!
          _roomSubscription?.cancel();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => GameScreen(
                roomId: widget.roomId,
                roomCode: widget.roomCode,
              ),
            ),
          );
        }
      },
      onError: (err) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lobby closed: $err'),
            backgroundColor: AppColors.primary,
          ),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
    );
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    super.dispose();
  }

  Future<void> _handleStartGame(int playerCount) async {
    debugPrint(
        'START GAME REQUEST: roomId=${widget.roomId}, playerCount=$playerCount, minPlayers=${GameConfig.minPlayers}');
    if (playerCount < GameConfig.minPlayers) {
      setState(() {
        _errorMessage =
            'At least ${GameConfig.minPlayers} players are required to start Mafia.';
      });
      return;
    }

    setState(() {
      _isStarting = true;
      _errorMessage = null;
    });

    try {
      final service = GameServiceProvider.instance.current;
      await service.startGame(widget.roomId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  Future<void> _handleLeaveRoom() async {
    final uid = AuthService.instance.currentUid;
    if (uid != null) {
      final service = GameServiceProvider.instance.current;
      await service.leaveRoom(roomId: widget.roomId, uid: uid);
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleAddTestBot(int currentCount) async {
    setState(() => _isAddingBot = true);
    try {
      final service = GameServiceProvider.instance.current;
      final botName = 'Bot $currentCount';
      await service.addTestPlayer(roomId: widget.roomId, name: botName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add bot: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAddingBot = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = GameServiceProvider.instance.current;
    final currentUid = AuthService.instance.currentUid;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleLeaveRoom();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'LOBBY',
            style: TextStyle(letterSpacing: 2.0, fontWeight: FontWeight.w900),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.exit_to_app_rounded,
                  color: AppColors.textSecondary),
              tooltip: 'Leave Room',
              onPressed: _handleLeaveRoom,
            ),
          ],
        ),
        body: SafeArea(
          child: StreamBuilder<List<Player>>(
            stream: service.streamPlayers(widget.roomId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('Error loading lobby: ${snapshot.error}'),
                );
              }

              if (!snapshot.hasData) {
                return const LoadingView(message: 'Loading players...');
              }

              final players = snapshot.data!;
              final isHost =
                  players.any((p) => p.uid == currentUid && p.isHost);
              final minPlayers = GameConfig.minPlayers;
              final canStart = players.length >= minPlayers;

              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Room code card
                    RoomCodeDisplay(roomCode: widget.roomCode),
                    const SizedBox(height: 10),

                    // Players header & count
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'PLAYERS',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: canStart
                                ? AppColors.success.withValues(alpha: 0.15)
                                : AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: canStart
                                  ? AppColors.success.withValues(alpha: 0.4)
                                  : AppColors.cardBorder,
                            ),
                          ),
                          child: Text(
                            '${players.length} / ${GameConfig.maxPlayers} (Min $minPlayers)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: canStart
                                  ? AppColors.success
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Real-time player list with avatar and HOST / READY tags
                    Expanded(
                      child: ListView.builder(
                        itemCount: players.length,
                        itemBuilder: (context, index) {
                          final player = players[index];
                          return PlayerCard(
                            player: player,
                            isCurrentPlayer: player.uid == currentUid,
                            subtitle: player.isHost ? 'HOST' : 'READY',
                          );
                        },
                      ),
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                              color: AppColors.danger, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Waiting state vs Ready state
                    if (!canStart) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.group_outlined,
                                size: 16, color: AppColors.warning),
                            const SizedBox(width: 8),
                            Text(
                              'WAITING FOR PLAYERS (${players.length} / $minPlayers)',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.success.withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_rounded,
                                color: AppColors.success, size: 16),
                            SizedBox(width: 8),
                            Text(
                              'READY TO PLAY',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Host controls vs Player waiting indicator
                    if (isHost) ...[
                      PrimaryButton(
                        key: const Key('start_game_button'),
                        label: 'START GAME',
                        isLoading: _isStarting,
                        icon: Icons.play_arrow_rounded,
                        onPressed: canStart
                            ? () => _handleStartGame(players.length)
                            : null,
                      ),
                      // Only visible when testingMode is explicitly enabled for development/testing
                      if (GameConfig.testingMode &&
                          players.length < GameConfig.maxPlayers) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: const Key('add_test_bot_button'),
                          icon: const Icon(Icons.smart_toy_outlined, size: 18),
                          label: Text(
                            'ADD TEST BOT (${players.length}/${GameConfig.maxPlayers})',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accent,
                            side: const BorderSide(
                                color: AppColors.accent, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isAddingBot
                              ? null
                              : () => _handleAddTestBot(players.length),
                        ),
                      ],
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Column(
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        AppColors.accent),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Waiting for host to start...',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textSecondary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              key: const Key('claim_host_button'),
                              icon: const Icon(Icons.swap_horiz_rounded,
                                  size: 14, color: AppColors.textMuted),
                              label: const Text(
                                'Host disconnected? Claim Host',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.textMuted),
                              ),
                              onPressed: () async {
                                try {
                                  await service.claimHost(widget.roomId);
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.toString())),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
