import 'package:flutter/material.dart';
import '../../models/player.dart';
import '../../models/private_vote.dart';
import '../../models/room.dart';
import '../../models/round_data.dart';
import '../../services/game_service_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/game_timer_widget.dart';
import '../../widgets/player_card.dart';
import '../../widgets/primary_button.dart';

class VotingPhaseView extends StatefulWidget {
  final String roomId;
  final Room room;
  final int roundNumber;
  final Player currentPlayer;
  final List<Player> allPlayers;
  final RoundData roundData;
  final PrivateVote? myVote;
  final bool isHost;

  const VotingPhaseView({
    super.key,
    required this.roomId,
    required this.room,
    required this.roundNumber,
    required this.currentPlayer,
    required this.allPlayers,
    required this.roundData,
    required this.myVote,
    this.isHost = false,
  });

  @override
  State<VotingPhaseView> createState() => _VotingPhaseViewState();
}

class _VotingPhaseViewState extends State<VotingPhaseView> {
  String? _selectedCandidateId;
  bool _isSubmitting = false;

  bool get _hasVoted => widget.myVote != null;

  Future<void> _handleConfirmVote() async {
    if (_selectedCandidateId == null || _hasVoted) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final service = GameServiceProvider.instance.current;
      await service.submitVote(
        roomId: widget.roomId,
        roundNumber: widget.roundNumber,
        uid: widget.currentPlayer.uid,
        targetId: _selectedCandidateId!,
      );
    } catch (e) {
      debugPrint('Error submitting vote: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAlive = widget.currentPlayer.isAlive;
    final livingPlayers = widget.allPlayers.where((p) => p.isAlive).toList();
    final votedUids = widget.roundData.votedUids;
    final votedCount = votedUids.length;
    final remainingVotes = livingPlayers.length - votedCount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: WHO DO YOU TRUST? + Timer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'WHO DO YOU TRUST?',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$votedCount / ${livingPlayers.length} PLAYERS HAVE VOTED',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GameTimerWidget(
                  endTimestampMillis:
                      widget.room.votingEndTimestamp?.millisecondsSinceEpoch,
                  onTimerExpired: () {
                    if (widget.isHost) {
                      final service = GameServiceProvider.instance.current;
                      service.resolveVotesOnTimeout(
                          widget.roomId, widget.roundNumber);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // List of candidate players with per-player progress badges
          Expanded(
            child: ListView.builder(
              itemCount: livingPlayers.length,
              itemBuilder: (context, index) {
                final player = livingPlayers[index];
                final isSelf = player.uid == widget.currentPlayer.uid;
                final hasVoted = votedUids.contains(player.uid);
                final canVoteForThisPlayer = isAlive && !_hasVoted && !isSelf;

                return PlayerCard(
                  player: player,
                  isSelected: _selectedCandidateId == player.uid,
                  isTargetable: canVoteForThisPlayer,
                  isCurrentPlayer: isSelf,
                  disabledReason: !isAlive
                      ? null
                      : isSelf
                          ? 'You cannot vote for yourself'
                          : null,
                  accentColor: AppColors.primary,
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: hasVoted
                          ? AppColors.success.withValues(alpha: 0.15)
                          : AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: hasVoted
                            ? AppColors.success.withValues(alpha: 0.4)
                            : AppColors.cardBorder,
                      ),
                    ),
                    child: Text(
                      hasVoted ? '✓ VOTED' : '○ THINKING',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color:
                            hasVoted ? AppColors.success : AppColors.textMuted,
                      ),
                    ),
                  ),
                  onTap: canVoteForThisPlayer
                      ? () {
                          setState(() {
                            _selectedCandidateId = player.uid;
                          });
                        }
                      : null,
                );
              },
            ),
          ),

          // Status & confirm button
          if (!isAlive) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('👻', style: TextStyle(fontSize: 16)),
                  SizedBox(width: 10),
                  Text(
                    'Eliminated — Spectating vote progress',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_hasVoted) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 20),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      '✓ VOTE LOCKED • Waiting for $remainingVotes player${remainingVotes == 1 ? "" : "s"}...',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            PrimaryButton(
              label: 'CONFIRM VOTE',
              isLoading: _isSubmitting,
              icon: Icons.how_to_vote_rounded,
              onPressed:
                  _selectedCandidateId != null ? _handleConfirmVote : null,
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
