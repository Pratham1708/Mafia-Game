import 'package:flutter/material.dart';
import '../../models/player.dart';
import '../../models/player_role.dart';
import '../../models/room.dart';
import '../../services/auth_service.dart';
import '../../services/game_service_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/player_card.dart';
import '../../widgets/primary_button.dart';

class GameOverView extends StatefulWidget {
  final Room room;
  final List<Player> allPlayers;
  final bool isHost;

  const GameOverView({
    super.key,
    required this.room,
    required this.allPlayers,
    this.isHost = false,
  });

  @override
  State<GameOverView> createState() => _GameOverViewState();
}

class _GameOverViewState extends State<GameOverView> {
  bool _isResetting = false;

  Future<void> _handlePlayAgain() async {
    setState(() => _isResetting = true);
    try {
      final service = GameServiceProvider.instance.current;
      await service.resetRoomForNewGame(widget.room.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to return to room: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isResetting = false);
      }
    }
  }

  Future<void> _handleExitToHome() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        title: const Text(
          'LEAVE THIS ROOM?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
            color: AppColors.textPrimary,
          ),
        ),
        content: const Text(
          'You\'ll leave this game and return to Home.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('LEAVE'),
          ),
        ],
      ),
    );

    if (shouldLeave == true && mounted) {
      final currentUid = AuthService.instance.currentUid;
      if (currentUid != null) {
        try {
          final service = GameServiceProvider.instance.current;
          await service.leaveRoom(roomId: widget.room.id, uid: currentUid);
        } catch (_) {}
      }
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMafiaWin = (widget.room.winner ?? '').toUpperCase() == 'MAFIA';
    final winnerTitle = isMafiaWin ? 'THE CITY FALLS' : 'THE TRUTH PREVAILS';
    final winnerSubtitle = isMafiaWin ? 'MAFIA WINS' : 'CIVILIANS WIN';
    final winnerDesc = isMafiaWin
        ? 'The Mafia has taken control.'
        : 'The Mafia has been eliminated.';
    final winnerColor = isMafiaWin ? AppColors.danger : AppColors.primary;

    final mafiaPlayers = widget.allPlayers.where((p) => p.role == PlayerRole.mafia).toList();
    final civilianPlayers = widget.allPlayers.where((p) => p.role != PlayerRole.mafia).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),

          // Dramatic Victory Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: winnerColor.withValues(alpha: 0.6), width: 2),
              boxShadow: [
                BoxShadow(
                  color: winnerColor.withValues(alpha: 0.18),
                  blurRadius: 36,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(
                  isMafiaWin ? Icons.masks_rounded : Icons.verified_rounded,
                  size: 54,
                  color: winnerColor,
                ),
                const SizedBox(height: 14),
                Text(
                  winnerTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3.0,
                    color: winnerColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  winnerSubtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  winnerDesc,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Mafia Team Breakdown
          if (mafiaPlayers.isNotEmpty) ...[
            const Row(
              children: [
                Icon(Icons.masks_outlined, size: 16, color: AppColors.danger),
                SizedBox(width: 8),
                Text(
                  'MAFIA',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...mafiaPlayers.map(
              (player) => PlayerCard(
                player: player,
                showRole: true,
                accentColor: AppColors.danger,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Civilians Team Breakdown
          if (civilianPlayers.isNotEmpty) ...[
            const Row(
              children: [
                Icon(Icons.shield_outlined, size: 16, color: AppColors.secondary),
                SizedBox(width: 8),
                Text(
                  'CIVILIANS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...civilianPlayers.map(
              (player) => PlayerCard(
                player: player,
                showRole: true,
                accentColor: AppColors.secondary,
              ),
            ),
          ],

          const SizedBox(height: 28),

          // Actions: PLAY AGAIN & EXIT TO HOME
          PrimaryButton(
            key: const Key('play_again_button'),
            label: 'PLAY AGAIN',
            isLoading: _isResetting,
            icon: Icons.replay_rounded,
            onPressed: _handlePlayAgain,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('exit_to_home_button'),
            icon: const Icon(Icons.home_rounded, size: 18, color: AppColors.textSecondary),
            label: const Text(
              'EXIT TO HOME',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: AppColors.textSecondary,
              ),
            ),
            onPressed: _handleExitToHome,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
