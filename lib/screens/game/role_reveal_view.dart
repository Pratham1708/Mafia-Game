import 'package:flutter/material.dart';
import '../../models/player.dart';
import '../../models/player_role.dart';
import '../../services/game_service_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';

class RoleRevealView extends StatefulWidget {
  final String roomId;
  final Player currentPlayer;
  final PlayerRole myRole;
  final bool isHost;

  const RoleRevealView({
    super.key,
    required this.roomId,
    required this.currentPlayer,
    required this.myRole,
    required this.isHost,
  });

  @override
  State<RoleRevealView> createState() => _RoleRevealViewState();
}

class _RoleRevealViewState extends State<RoleRevealView> {
  bool _isContinuing = false;
  bool _hasAcknowledged = false;

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

  IconData _getRoleIcon(PlayerRole role) {
    switch (role) {
      case PlayerRole.mafia:
        return Icons.masks_outlined;
      case PlayerRole.detective:
        return Icons.search_rounded;
      case PlayerRole.doctor:
        return Icons.medical_services_outlined;
      case PlayerRole.bodyguard:
        return Icons.shield_outlined;
      case PlayerRole.vigilante:
        return Icons.gps_fixed_rounded;
      case PlayerRole.civilian:
        return Icons.person_outline_rounded;
      case PlayerRole.unknown:
        return Icons.help_outline_rounded;
    }
  }

  String _getRoleHeadline(PlayerRole role) {
    switch (role) {
      case PlayerRole.mafia:
        return 'You are part of the Mafia.\nEliminate the civilians without getting caught.';
      case PlayerRole.detective:
        return 'Investigate one player each round.\nFind the Mafia before they find you.';
      case PlayerRole.doctor:
        return 'Protect one player each round.';
      case PlayerRole.bodyguard:
        return 'Protect one player.\nIf Mafia attacks your target, you may sacrifice yourself to save them.';
      case PlayerRole.vigilante:
        return 'You have one opportunity to eliminate a player.';
      case PlayerRole.civilian:
        return 'Watch carefully.\nFind the Mafia through discussion and voting.';
      case PlayerRole.unknown:
        return 'Synchronizing your private identity...';
    }
  }

  Future<void> _handleContinue() async {
    setState(() => _isContinuing = true);

    try {
      final service = GameServiceProvider.instance.current;
      await service.advanceToActions(widget.roomId);
    } catch (e) {
      debugPrint('Error advancing to actions: $e');
    } finally {
      if (mounted) {
        setState(() => _isContinuing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.myRole;
    final roleColor = _getRoleColor(role);
    final iconData = _getRoleIcon(role);
    final headline = _getRoleHeadline(role);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
      child: Column(
        children: [
          const SizedBox(height: 16),
          const Text(
            'YOUR ROLE',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 3.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),

          // Dramatic role card with glowing aura
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: roleColor.withValues(alpha: 0.6),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: roleColor.withValues(alpha: 0.18),
                  blurRadius: 32,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              children: [
                // Subtle role icon badge
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: roleColor.withValues(alpha: 0.14),
                    border: Border.all(color: roleColor.withValues(alpha: 0.4), width: 1.5),
                  ),
                  child: Center(
                    child: Icon(iconData, size: 36, color: roleColor),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  role.displayName.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4.0,
                    color: roleColor,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    role.teamDisplayName.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: roleColor,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  headline,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Objective reminder
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Text(
                  'Keep your identity secret from everyone.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // Action button
          if (widget.isHost)
            PrimaryButton(
              label: 'GOT IT',
              isLoading: _isContinuing,
              backgroundColor: roleColor,
              icon: Icons.check_rounded,
              onPressed: _handleContinue,
            )
          else ...[
            if (!_hasAcknowledged)
              PrimaryButton(
                label: 'GOT IT',
                backgroundColor: roleColor,
                icon: Icons.check_rounded,
                onPressed: () {
                  setState(() => _hasAcknowledged = true);
                },
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
                          'Waiting for host to continue...',
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    TextButton(
                      key: const Key('claim_host_role_reveal'),
                      onPressed: () async {
                        try {
                          await GameServiceProvider.instance.current
                              .claimHost(widget.roomId);
                        } catch (_) {}
                      },
                      child: const Text(
                        'Host disconnected? Claim Host',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
