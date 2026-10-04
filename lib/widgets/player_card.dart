import 'package:flutter/material.dart';
import '../models/player.dart';
import '../models/player_role.dart';
import '../theme/app_theme.dart';
import '../utils/player_avatar.dart';

/// Unified Player Card component used across lobby, action phases, discussion,
/// voting, round result, and game over.
///
/// Fully supports:
/// - alive / dead / eliminated
/// - selected state (with prominent checkmark icon + thick border)
/// - current player indicator ('YOU')
/// - host crown badge ('👑 HOST')
/// - targetable vs non-targetable (with reason)
/// - waiting state indicator
/// - optional role display (post game-over or reveal)
class PlayerCard extends StatelessWidget {
  final Player player;
  final bool isCurrentPlayer;
  final bool isSelected;
  final bool isTargetable;
  final String? disabledReason;
  final String? subtitle;
  final bool isWaiting;
  final bool showRole;
  final Color? accentColor;
  final VoidCallback? onTap;
  final Widget? trailing;

  const PlayerCard({
    super.key,
    required this.player,
    this.isCurrentPlayer = false,
    this.isSelected = false,
    this.isTargetable = true,
    this.disabledReason,
    this.subtitle,
    this.isWaiting = false,
    this.showRole = false,
    this.accentColor,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = accentColor ?? AppColors.primary;
    final bool isClickable = isTargetable && player.isAlive && onTap != null;

    final Color borderColor;
    if (isSelected) {
      borderColor = effectiveColor;
    } else if (isCurrentPlayer) {
      borderColor = AppColors.accent.withValues(alpha: 0.6);
    } else if (!player.isAlive) {
      borderColor = AppColors.cardBorder.withValues(alpha: 0.25);
    } else if (!isTargetable) {
      borderColor = AppColors.cardBorder.withValues(alpha: 0.35);
    } else {
      borderColor = AppColors.cardBorder;
    }

    final Color bgColor;
    if (isSelected) {
      bgColor = effectiveColor.withValues(alpha: 0.16);
    } else if (!player.isAlive) {
      bgColor = AppColors.surface.withValues(alpha: 0.35);
    } else if (!isTargetable) {
      bgColor = AppColors.surface.withValues(alpha: 0.45);
    } else {
      bgColor = AppColors.surface;
    }

    final Widget content = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: isSelected ? 2.5 : (isCurrentPlayer ? 1.5 : 1.0),
        ),
      ),
      child: Row(
        children: [
          // Selection or status badge
          if (onTap != null) ...[
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? effectiveColor
                      : (isTargetable
                          ? AppColors.textMuted
                          : AppColors.cardBorder),
                  width: 2,
                ),
                color: isSelected ? effectiveColor : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 8),
          ] else ...[
            // Status dot / dead skull indicator
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    player.isAlive ? AppColors.success : AppColors.eliminated,
                boxShadow: player.isAlive
                    ? [
                        BoxShadow(
                          color: AppColors.success.withValues(alpha: 0.4),
                          blurRadius: 6,
                        )
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Player avatar identity badge
          Builder(
            builder: (context) {
              final avatar = PlayerAvatar.fromPlayer(player.uid, player.name);
              return Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: player.isAlive
                        ? avatar.accentColor.withValues(alpha: 0.5)
                        : AppColors.cardBorder,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  avatar.icon,
                  size: 16,
                  color:
                      player.isAlive ? avatar.accentColor : AppColors.textMuted,
                ),
              );
            },
          ),
          const SizedBox(width: 8),

          // Player name, badges, and subtitle / reason
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        player.name,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: (isSelected || isCurrentPlayer)
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: !player.isAlive
                              ? AppColors.textMuted
                              : (!isTargetable
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary),
                          decoration: player.isAlive
                              ? null
                              : TextDecoration.lineThrough,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
                if (isCurrentPlayer || player.isHost) ...[
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (isCurrentPlayer)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'YOU',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                      if (player.isHost)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.5),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('👑', style: TextStyle(fontSize: 8)),
                              SizedBox(width: 2),
                              Text(
                                'HOST',
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.warning,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
                if (disabledReason != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    disabledReason!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ] else if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Waiting spinner
          if (isWaiting) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ],

          // Elimination badge
          if (!player.isAlive) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              margin: const EdgeInsets.only(left: 6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'ELIMINATED',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: AppColors.primaryLight,
                ),
              ),
            ),
          ],

          // Role reveal (at game over or reveal phase)
          if (showRole && player.role != PlayerRole.unknown) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(player.role.iconEmoji,
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  Text(
                    player.role.displayName,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );

    if (isClickable) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: content,
          ),
        ),
      );
    }

    return content;
  }
}
