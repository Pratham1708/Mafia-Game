import 'package:flutter/material.dart';
import '../../models/player.dart';
import '../../models/room.dart';
import '../../models/round_data.dart';
import '../../services/game_service_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';

class EliminationView extends StatefulWidget {
  final Room room;
  final List<Player> allPlayers;
  final RoundData? roundData;
  final bool isHost;

  const EliminationView({
    super.key,
    required this.room,
    required this.allPlayers,
    this.roundData,
    required this.isHost,
  });

  @override
  State<EliminationView> createState() => _EliminationViewState();
}

class _EliminationViewState extends State<EliminationView> {
  bool _isContinuing = false;

  Future<void> _handleNextRound() async {
    setState(() {
      _isContinuing = true;
    });

    try {
      final service = GameServiceProvider.instance.current;
      await service.advanceToNextRoundOrEnd(widget.room.id);
    } catch (e) {
      debugPrint('Error advancing round: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isContinuing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final eliminatedUid = widget.room.votedOutThisRound;
    final eliminatedPlayer = widget.allPlayers.cast<Player?>().firstWhere(
          (p) => p?.uid == eliminatedUid,
          orElse: () => null,
        );

    final livingCount = widget.allPlayers.where((p) => p.isAlive).length;
    final voteTally = widget.roundData?.voteTally ?? <String, int>{};
    final sortedTally = voteTally.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVotes = sortedTally.isNotEmpty ? sortedTally.first.value : 1;
    final winningVotes = eliminatedUid != null ? (voteTally[eliminatedUid] ?? 0) : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),

          const Center(
            child: Text(
              'VOTE RESULT',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 3.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Aggregated Vote Reveal Presentation
          if (sortedTally.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(18),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'THE VOTE IS IN',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...sortedTally.map((entry) {
                    final targetPlayer = widget.allPlayers
                        .cast<Player?>()
                        .firstWhere((p) => p?.uid == entry.key,
                            orElse: () => null);
                    final targetName = targetPlayer?.name ?? 'Player';
                    final isEliminated = entry.key == eliminatedUid;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5.0),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(
                              targetName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isEliminated
                                    ? AppColors.danger
                                    : AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 5,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: maxVotes > 0 ? entry.value / maxVotes : 0,
                                minHeight: 8,
                                backgroundColor: AppColors.cardBorder,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isEliminated
                                      ? AppColors.danger
                                      : AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${entry.value} ${entry.value == 1 ? "vote" : "votes"}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],

          // Elimination Outcome Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: eliminatedPlayer != null
                    ? AppColors.danger.withValues(alpha: 0.6)
                    : AppColors.cardBorder,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: (eliminatedPlayer != null ? AppColors.danger : AppColors.cardBorder)
                      .withValues(alpha: 0.12),
                  blurRadius: 28,
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(
                  eliminatedPlayer != null ? Icons.gavel_rounded : Icons.handshake_outlined,
                  size: 48,
                  color: eliminatedPlayer != null ? AppColors.danger : AppColors.warning,
                ),
                const SizedBox(height: 14),
                if (eliminatedPlayer != null) ...[
                  Text(
                    eliminatedPlayer.name.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$winningVotes VOTES • ELIMINATED',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      color: AppColors.danger,
                    ),
                  ),
                ] else ...[
                  const Text(
                    'NO CONSENSUS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      color: AppColors.warning,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'The vote is tied.\nNobody is eliminated.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$livingCount PLAYERS REMAINING',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Only the host can advance to the next round.
          if (widget.isHost)
            PrimaryButton(
              label: 'CONTINUE TO NEXT ROUND',
              isLoading: _isContinuing,
              icon: Icons.arrow_forward_rounded,
              onPressed: _handleNextRound,
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Waiting for host to start next round...',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  TextButton(
                    key: const Key('claim_host_elimination'),
                    onPressed: () async {
                      try {
                        await GameServiceProvider.instance.current
                            .claimHost(widget.room.id);
                      } catch (_) {}
                    },
                    child: const Text(
                      'Host disconnected? Claim Host',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.textMuted),
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
