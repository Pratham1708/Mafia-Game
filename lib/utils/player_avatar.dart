import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Lightweight generated visual identity for players in Mafia.
/// Provides a sleek, non-cartoonish identity (e.g. Raven, Wolf, Fox, Snake, Crow, Owl)
/// so players are recognizable in the lobby and during voting without needing profile photos.
class PlayerAvatar {
  final String label;
  final IconData icon;
  final Color accentColor;

  const PlayerAvatar({
    required this.label,
    required this.icon,
    required this.accentColor,
  });

  static const List<PlayerAvatar> _identities = [
    PlayerAvatar(
      label: 'Raven',
      icon: Icons.air_rounded,
      accentColor: AppColors.primary,
    ),
    PlayerAvatar(
      label: 'Wolf',
      icon: Icons.nightlight_round,
      accentColor: AppColors.secondary,
    ),
    PlayerAvatar(
      label: 'Fox',
      icon: Icons.flash_on_rounded,
      accentColor: AppColors.warning,
    ),
    PlayerAvatar(
      label: 'Snake',
      icon: Icons.all_inclusive_rounded,
      accentColor: AppColors.success,
    ),
    PlayerAvatar(
      label: 'Crow',
      icon: Icons.remove_red_eye_outlined,
      accentColor: Color(0xFFA855F7),
    ),
    PlayerAvatar(
      label: 'Owl',
      icon: Icons.visibility_outlined,
      accentColor: Color(0xFF38BDF8),
    ),
    PlayerAvatar(
      label: 'Hawk',
      icon: Icons.navigation_rounded,
      accentColor: Color(0xFFF43F5E),
    ),
    PlayerAvatar(
      label: 'Panther',
      icon: Icons.shield_moon_outlined,
      accentColor: Color(0xFF818CF8),
    ),
    PlayerAvatar(
      label: 'Falcon',
      icon: Icons.explore_outlined,
      accentColor: Color(0xFF34D399),
    ),
    PlayerAvatar(
      label: 'Viper',
      icon: Icons.offline_bolt_outlined,
      accentColor: Color(0xFFFB923C),
    ),
    PlayerAvatar(
      label: 'Lynx',
      icon: Icons.adjust_rounded,
      accentColor: Color(0xFFE879F9),
    ),
    PlayerAvatar(
      label: 'Stag',
      icon: Icons.forest_outlined,
      accentColor: Color(0xFF2DD4BF),
    ),
  ];

  static PlayerAvatar fromPlayer(String uid, String name) {
    if (uid.isEmpty) return _identities[0];
    final index = (uid.hashCode.abs() + name.hashCode.abs()) % _identities.length;
    return _identities[index];
  }
}
