import 'package:flutter/material.dart';
import '../../models/player.dart';
import '../../models/player_role.dart';
import '../../models/private_action.dart';
import '../../models/round_data.dart';
import '../../services/game_service_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/player_card.dart';
import '../../widgets/primary_button.dart';

class ActionsPhaseView extends StatefulWidget {
  final String roomId;
  final int roundNumber;
  final Player currentPlayer;
  final PlayerRole myRole;
  final List<Player> allPlayers;
  final RoundData roundData;
  final PrivateAction? myAction;
  final bool hasUsedAbility;

  const ActionsPhaseView({
    super.key,
    required this.roomId,
    required this.roundNumber,
    required this.currentPlayer,
    required this.myRole,
    required this.allPlayers,
    required this.roundData,
    required this.myAction,
    this.hasUsedAbility = false,
  });

  @override
  State<ActionsPhaseView> createState() => _ActionsPhaseViewState();
}

class _ActionsPhaseViewState extends State<ActionsPhaseView> {
  String? _selectedTargetId;
  bool _isSubmitting = false;

  bool get _hasSubmitted => widget.myAction != null;

  Color _getRoleColor(PlayerRole role) {
    switch (role) {
      case PlayerRole.mafia:
        return AppColors.danger;
      case PlayerRole.detective:
        return AppColors.detectiveBlue;
      case PlayerRole.doctor:
        return AppColors.doctorGreen;
      case PlayerRole.bodyguard:
        return AppColors.bodyguardAmber;
      case PlayerRole.vigilante:
        return AppColors.vigilantePurple;
      case PlayerRole.civilian:
        return AppColors.civilianSlate;
      case PlayerRole.unknown:
        return AppColors.textSecondary;
    }
  }

  String get _actionTitle {
    switch (widget.myRole) {
      case PlayerRole.mafia:
        return 'CHOOSE YOUR TARGET';
      case PlayerRole.detective:
        return 'INVESTIGATE';
      case PlayerRole.doctor:
        return 'PROTECT';
      case PlayerRole.bodyguard:
        return 'PROTECT';
      case PlayerRole.vigilante:
        return 'CHOOSE YOUR TARGET';
      default:
        return 'SECRET ACTIONS';
    }
  }

  String get _actionSubtitle {
    switch (widget.myRole) {
      case PlayerRole.mafia:
        return 'Who do you think is dangerous?';
      case PlayerRole.detective:
        return 'Choose one player to uncover their true identity.';
      case PlayerRole.doctor:
        return 'Who should survive the night?';
      case PlayerRole.bodyguard:
        return 'Protect another player. If Mafia attacks them, you sacrifice yourself to save them.';
      case PlayerRole.vigilante:
        return 'One-time elimination shot. Choose carefully.';
      default:
        return 'Civilians do not perform secret actions.';
    }
  }

  String get _actionButtonLabel {
    switch (widget.myRole) {
      case PlayerRole.mafia:
      case PlayerRole.vigilante:
      case PlayerRole.detective:
      case PlayerRole.doctor:
      case PlayerRole.bodyguard:
        return 'CONFIRM';
      default:
        return 'CONFIRM ACTION';
    }
  }

  Future<void> _handleSubmitAction([String? overrideTarget]) async {
    final target = overrideTarget ?? _selectedTargetId;
    if (target == null || _hasSubmitted) return;

    setState(() => _isSubmitting = true);

    try {
      final service = GameServiceProvider.instance.current;
      await service.submitAction(
        roomId: widget.roomId,
        roundNumber: widget.roundNumber,
        uid: widget.currentPlayer.uid,
        targetId: target,
        role: widget.myRole,
      );
    } catch (e) {
      debugPrint('Error submitting action: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.myRole;
    final roleColor = _getRoleColor(role);
    final isAlive = widget.currentPlayer.isAlive;
    final livingPlayers = widget.allPlayers.where((p) => p.isAlive).toList();

    if (!isAlive) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('💀', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              const Text(
                'YOU HAVE BEEN ELIMINATED',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You can observe the round as a spectator.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    // Civilian — waiting for special roles
    if (!role.hasSecretAction) {
      final completedActions = widget.roundData.actionsCount;

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceElevated,
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: const Icon(Icons.remove_red_eye_outlined, size: 32, color: AppColors.secondary),
              ),
              const SizedBox(height: 20),
              const Text(
                'YOU HAVE NO SECRET ACTION',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Watch carefully.\nSomeone\'s lying.\nSomeone\'s hiding something.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Text(
                  'Waiting for other players... ($completedActions submitted)',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 20),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Vigilante with already-used ability
    if (role == PlayerRole.vigilante && widget.hasUsedAbility) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.gps_off_rounded, size: 48, color: AppColors.vigilantePurple),
              const SizedBox(height: 16),
              const Text(
                'ABILITY CONSUMED',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: AppColors.vigilantePurple,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You have already taken your one-time shot.\nYou are observing the night in silence.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              if (!_hasSubmitted)
                OutlinedButton(
                  onPressed: () => _handleSubmitAction(''),
                  child: const Text('CONFIRM OBSERVATION'),
                )
              else
                const Text(
                  'Waiting for other players...',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
            ],
          ),
        ),
      );
    }

    // Active role target selection
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: roleColor.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ROUND ${widget.roundNumber} • YOUR MOVE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: roleColor,
                      ),
                    ),
                    Text(
                      role.displayName.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _actionTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _actionSubtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Player target list
          Expanded(
            child: ListView.builder(
              itemCount: livingPlayers.length,
              itemBuilder: (context, index) {
                final player = livingPlayers[index];
                final isSelf = player.uid == widget.currentPlayer.uid;

                bool canTarget = true;
                bool selfBlocked = false;

                if (role == PlayerRole.bodyguard || role == PlayerRole.doctor) {
                  if (role == PlayerRole.bodyguard && isSelf) {
                    canTarget = false;
                    selfBlocked = true;
                  }
                } else if (role == PlayerRole.mafia) {
                  if (isSelf) {
                    canTarget = false;
                    selfBlocked = true;
                  }
                } else if (role == PlayerRole.detective) {
                  if (isSelf) {
                    canTarget = false;
                    selfBlocked = true;
                  }
                } else if (role == PlayerRole.vigilante) {
                  if (isSelf) {
                    canTarget = false;
                    selfBlocked = true;
                  }
                }

                return PlayerCard(
                  player: player,
                  isSelected: _selectedTargetId == player.uid,
                  isTargetable: !_hasSubmitted && canTarget,
                  disabledReason: selfBlocked ? 'You cannot target yourself' : null,
                  accentColor: roleColor,
                  onTap: () {
                    if (!_hasSubmitted && canTarget) {
                      setState(() => _selectedTargetId = player.uid);
                    }
                  },
                );
              },
            ),
          ),

          if (_hasSubmitted) ...[
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
                  Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Action locked. Waiting for other players...',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            PrimaryButton(
              label: _actionButtonLabel,
              backgroundColor: roleColor,
              isLoading: _isSubmitting,
              icon: Icons.check_rounded,
              onPressed: _selectedTargetId != null ? () => _handleSubmitAction() : null,
            ),
            if (role == PlayerRole.vigilante) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _isSubmitting ? null : () => _handleSubmitAction(''),
                child: const Text('SKIP ACTION (SAVE SHOT)'),
              ),
            ],
          ],

          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
