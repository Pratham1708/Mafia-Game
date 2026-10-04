import 'package:flutter/material.dart';
import '../models/player.dart';
import 'player_card.dart';

/// Legacy adapter for [PlayerCard] providing selection list behavior.
class PlayerSelectionCard extends StatelessWidget {
  final Player player;
  final bool isSelected;
  final bool isEnabled;
  final String? disabledReason;
  final VoidCallback? onTap;

  const PlayerSelectionCard({
    super.key,
    required this.player,
    this.isSelected = false,
    this.isEnabled = true,
    this.disabledReason,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PlayerCard(
      player: player,
      isSelected: isSelected,
      isTargetable: isEnabled,
      disabledReason: disabledReason,
      onTap: isEnabled ? onTap : null,
    );
  }
}
