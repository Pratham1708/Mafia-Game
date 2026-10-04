import 'package:flutter/material.dart';
import '../../models/player.dart';
import '../../models/player_role.dart';
import '../../models/private_result.dart';
import '../../models/room.dart';
import '../../models/round_data.dart';
import '../../services/game_service_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';

class RoundResultView extends StatefulWidget {
  final Room room;
  final Player currentPlayer;
  final PlayerRole myRole;
  final List<Player> allPlayers;
  final RoundData roundData;
  final PrivateResult? myResult;
  final bool isHost;

  const RoundResultView({
    super.key,
    required this.room,
    required this.currentPlayer,
    required this.myRole,
    required this.allPlayers,
    required this.roundData,
    required this.myResult,
    required this.isHost,
  });

  @override
  State<RoundResultView> createState() => _RoundResultViewState();
}

class _RoundResultViewState extends State<RoundResultView> {
  bool _isAdvancing = false;

  Future<void> _handleProceedToDiscussion() async {
    setState(() => _isAdvancing = true);
    try {
      final service = GameServiceProvider.instance.current;
      await service.advanceToDiscussion(widget.room.id);
    } catch (e) {
      debugPrint('Error advancing to discussion: $e');
    } finally {
      if (mounted) setState(() => _isAdvancing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eliminatedIds = widget.roundData.eliminatedPlayerIds.isNotEmpty
        ? widget.roundData.eliminatedPlayerIds
        : (widget.room.eliminatedThisRound != null
            ? [widget.room.eliminatedThisRound!]
            : <String>[]);

    final eliminatedPlayers = eliminatedIds
        .map((id) => widget.allPlayers.cast<Player?>().firstWhere(
              (p) => p?.uid == id,
              orElse: () => null,
            ))
        .whereType<Player>()
        .toList();

    final isDetective = widget.myRole == PlayerRole.detective;
    final isBodyguard = widget.myRole == PlayerRole.bodyguard;
    final hasBodyguardIntercepted =
        isBodyguard && (widget.myResult?.bodyguardIntercepted == true);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'ROUND RESULT',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 3.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Main cinematic public result card
          Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: eliminatedPlayers.isNotEmpty
                    ? AppColors.danger.withValues(alpha: 0.6)
                    : AppColors.success.withValues(alpha: 0.6),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: (eliminatedPlayers.isNotEmpty ? AppColors.danger : AppColors.success)
                      .withValues(alpha: 0.15),
                  blurRadius: 32,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(
                  eliminatedPlayers.isNotEmpty
                      ? Icons.warning_amber_rounded
                      : Icons.shield_outlined,
                  size: 56,
                  color: eliminatedPlayers.isNotEmpty ? AppColors.danger : AppColors.success,
                ),
                const SizedBox(height: 16),
                Text(
                  eliminatedPlayers.isEmpty
                      ? 'NO ONE WAS ELIMINATED'
                      : 'SOMEONE DIDN\'T MAKE IT',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    color: eliminatedPlayers.isNotEmpty
                        ? AppColors.danger
                        : AppColors.success,
                  ),
                ),
                const SizedBox(height: 12),
                if (eliminatedPlayers.isEmpty)
                  const Text(
                    'Everyone survived the night.\nDoctor protection succeeded or no attack was made.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
                  )
                else if (eliminatedPlayers.length == 1) ...[
                  Text(
                    eliminatedPlayers.first.name.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'is out.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.danger,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The investigation continues...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textMuted,
                    ),
                  ),
                ] else ...[
                  Column(
                    children: eliminatedPlayers
                        .map(
                          (p) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Text(
                              '• ${p.name.toUpperCase()} is out.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The investigation continues...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Private Bodyguard Sacrifice Card — ONLY visible to the Bodyguard
          if (hasBodyguardIntercepted) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_rounded, color: AppColors.warning, size: 28),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YOU SACRIFICED YOURSELF',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: AppColors.warning,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'You intercepted an attack.\nYour target survived.\nYou are eliminated.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Private Detective Result Card — ONLY visible to Detective
          if (isDetective && widget.myResult != null && widget.myResult!.targetId.isNotEmpty) ...[
            const SizedBox(height: 16),
            Builder(builder: (context) {
              final targetId = widget.myResult!.targetId;
              final isTargetMafia = widget.myResult!.isMafia;
              final targetPlayer = widget.allPlayers.cast<Player?>().firstWhere(
                    (p) => p?.uid == targetId,
                    orElse: () => null,
                  );
              final targetName = targetPlayer?.name ?? 'Target';
              final resultColor = isTargetMafia ? AppColors.danger : AppColors.success;

              return Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: resultColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: resultColor.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isTargetMafia ? Icons.warning_rounded : Icons.verified_user_rounded,
                      color: resultColor,
                      size: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CONFIDENTIAL INVESTIGATION',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: AppColors.detectiveBlue,
                            ),
                          ),
                          const SizedBox(height: 4),
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                              children: [
                                TextSpan(
                                  text: targetName,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const TextSpan(text: ' is '),
                                TextSpan(
                                  text: isTargetMafia ? 'MAFIA' : 'NOT MAFIA',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: resultColor,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],

          const SizedBox(height: 28),

          // Host continue vs spectator/player waiting
          if (widget.isHost)
            PrimaryButton(
              label: 'CONTINUE',
              isLoading: _isAdvancing,
              icon: Icons.arrow_forward_rounded,
              onPressed: _handleProceedToDiscussion,
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Waiting for host to continue...',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}