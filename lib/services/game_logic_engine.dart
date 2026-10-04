import 'dart:math';
import '../models/player_role.dart';
import '../models/player.dart';

/// Pure, testable game logic engine for Mafia game rules.
class GameLogicEngine {
  /// Generates the exact role distribution according to player count (6 to 12).
  ///
  /// Table:
  /// 6:  1 Mafia, 1 Detective, 1 Doctor, 3 Civilians
  /// 7:  2 Mafia, 1 Detective, 1 Doctor, 3 Civilians
  /// 8:  2 Mafia, 1 Detective, 1 Doctor, 4 Civilians
  /// 9:  2 Mafia, 1 Detective, 1 Doctor, 1 Bodyguard, 4 Civilians
  /// 10: 3 Mafia, 1 Detective, 1 Doctor, 1 Bodyguard, 4 Civilians
  /// 11: 3 Mafia, 1 Detective, 1 Doctor, 1 Bodyguard, 1 Vigilante, 4 Civilians
  /// 12: 3 Mafia, 1 Detective, 1 Doctor, 1 Bodyguard, 1 Vigilante, 5 Civilians
  static List<PlayerRole> getRoleDistribution(int playerCount) {
    if (playerCount < 6) {
      // Testing mode distribution for 4–5 players (covers all Phase 3 roles)
      return [
        PlayerRole.mafia,
        PlayerRole.detective,
        PlayerRole.doctor,
        if (playerCount >= 4) PlayerRole.bodyguard,
        if (playerCount >= 5) PlayerRole.vigilante,
      ].sublist(0, playerCount);
    }

    final int mafiaCount;
    final int detectiveCount = 1;
    final int doctorCount = 1;
    final int bodyguardCount;
    final int vigilanteCount;

    switch (playerCount) {
      case 6:
        mafiaCount = 1;
        bodyguardCount = 0;
        vigilanteCount = 0;
        break;
      case 7:
        mafiaCount = 2;
        bodyguardCount = 0;
        vigilanteCount = 0;
        break;
      case 8:
        mafiaCount = 2;
        bodyguardCount = 0;
        vigilanteCount = 0;
        break;
      case 9:
        mafiaCount = 2;
        bodyguardCount = 1;
        vigilanteCount = 0;
        break;
      case 10:
        mafiaCount = 3;
        bodyguardCount = 1;
        vigilanteCount = 0;
        break;
      case 11:
        mafiaCount = 3;
        bodyguardCount = 1;
        vigilanteCount = 1;
        break;
      case 12:
      default:
        mafiaCount = 3;
        bodyguardCount = 1;
        vigilanteCount = 1;
        break;
    }

    final int civilianCount = playerCount -
        (mafiaCount +
            detectiveCount +
            doctorCount +
            bodyguardCount +
            vigilanteCount);

    final List<PlayerRole> roles = [];
    roles.addAll(List.filled(mafiaCount, PlayerRole.mafia));
    roles.addAll(List.filled(detectiveCount, PlayerRole.detective));
    roles.addAll(List.filled(doctorCount, PlayerRole.doctor));
    if (bodyguardCount > 0)
      roles.addAll(List.filled(bodyguardCount, PlayerRole.bodyguard));
    if (vigilanteCount > 0)
      roles.addAll(List.filled(vigilanteCount, PlayerRole.vigilante));
    roles.addAll(List.filled(civilianCount, PlayerRole.civilian));

    return roles;
  }

  /// Shuffles and assigns roles to player UIDs.
  static Map<String, PlayerRole> assignRoles(
    List<String> playerUids, [
    Random? random,
  ]) {
    final roles = getRoleDistribution(playerUids.length);
    final shuffledRoles = List<PlayerRole>.from(roles)
      ..shuffle(random ?? Random.secure());

    final Map<String, PlayerRole> assignments = {};
    for (int i = 0; i < playerUids.length; i++) {
      assignments[playerUids[i]] = shuffledRoles[i];
    }
    return assignments;
  }

  /// Resolves the Mafia's target selection.
  ///
  /// Mechanism:
  /// - Each Mafia submits a target UID.
  /// - Calculates majority vote among submitted targets.
  /// - If tied, picks the target whose UID sorts first alphabetically.
  ///   This ensures deterministic resolution across all clients.
  static String? resolveMafiaTarget(Map<String, String> mafiaVotes) {
    if (mafiaVotes.isEmpty) return null;

    final voteCounts = <String, int>{};
    for (final target in mafiaVotes.values) {
      voteCounts[target] = (voteCounts[target] ?? 0) + 1;
    }

    int maxVotes = 0;
    for (final count in voteCounts.values) {
      if (count > maxVotes) maxVotes = count;
    }

    final tiedTargets = voteCounts.entries
        .where((e) => e.value == maxVotes)
        .map((e) => e.key)
        .toList()
      ..sort(); // Deterministic tie-break

    return tiedTargets.isNotEmpty ? tiedTargets.first : null;
  }

  /// Resolves secret actions for the round with deterministic server authority.
  ///
  /// Order of resolution:
  /// 1. Collect actions (Mafia, Doctor, Bodyguard, Vigilante, Detective)
  /// 2. Resolve Mafia target
  /// 3. Resolve Bodyguard interception:
  ///    - If Mafia target == Bodyguard target: Bodyguard intercepts attack!
  ///      Protected player survives Mafia strike.
  ///      Bodyguard receives the lethal attack.
  /// 4. Resolve Doctor protection:
  ///    - Doctor shields doctorTarget from lethal attacks this round.
  ///    - If Doctor protected Bodyguard who intercepted: Bodyguard survives!
  ///    - If Doctor protected Mafia target (not intercepted): target survives!
  ///    - If Doctor protected Vigilante target: target survives!
  /// 5. Resolve Vigilante attack:
  ///    - One-time elimination. If used previously or target == doctorTarget, target survives.
  ///    - Otherwise, target is eliminated.
  /// 6. Resolve Detective investigations.
  /// 7. Apply eliminations and return deterministic result.
  static ActionResolutionResult resolveSecretActions({
    required String? mafiaTarget,
    required String? doctorTarget,
    String? bodyguardTarget,
    String? bodyguardUid,
    String? vigilanteTarget,
    String? vigilanteUid,
    bool vigilanteAlreadyUsed = false,
    required Map<String, PlayerRole> playerRoles,
    Map<String, String>? detectiveTargets, // detectiveUid -> targetUid
  }) {
    final Set<String> eliminatedUids = {};
    bool bodyguardIntercepted = false;
    bool vigilanteUsedAbility = false;

    // 1 & 2. Mafia attack & Bodyguard interception
    if (mafiaTarget != null) {
      if (bodyguardTarget != null &&
          bodyguardUid != null &&
          bodyguardTarget == mafiaTarget &&
          bodyguardTarget != bodyguardUid) {
        // Bodyguard intercepts the attack!
        bodyguardIntercepted = true;
        // Bodyguard takes the lethal blow unless protected by Doctor
        if (doctorTarget != bodyguardUid) {
          eliminatedUids.add(bodyguardUid);
        }
      } else {
        // No interception: Doctor protection check on mafiaTarget
        if (doctorTarget != mafiaTarget) {
          eliminatedUids.add(mafiaTarget);
        }
      }
    }

    // 3. Vigilante attack
    if (vigilanteTarget != null &&
        vigilanteTarget.isNotEmpty &&
        vigilanteTarget != 'skip' &&
        !vigilanteAlreadyUsed &&
        vigilanteUid != null &&
        vigilanteTarget != vigilanteUid) {
      vigilanteUsedAbility = true;
      if (doctorTarget != vigilanteTarget) {
        eliminatedUids.add(vigilanteTarget);
      }
    }

    // 4. Detective investigations: detectiveUid -> {targetId: ..., isMafia: ...}
    final Map<String, bool> detectiveResults = {};
    if (detectiveTargets != null) {
      detectiveTargets.forEach((detectiveUid, targetUid) {
        final targetRole = playerRoles[targetUid];
        final isMafia = targetRole == PlayerRole.mafia;
        detectiveResults[detectiveUid] = isMafia;
      });
    }

    // Deterministic sorted list of eliminated player UIDs
    final List<String> sortedEliminated = eliminatedUids.toList()..sort();
    final String? primaryEliminatedId =
        sortedEliminated.isNotEmpty ? sortedEliminated.first : null;

    final String publicMessage;
    if (sortedEliminated.isEmpty) {
      publicMessage = 'No player was eliminated this round.';
    } else if (sortedEliminated.length == 1) {
      publicMessage = 'A player was eliminated this round.';
    } else {
      publicMessage =
          '${sortedEliminated.length} players were eliminated this round.';
    }

    return ActionResolutionResult(
      eliminatedPlayerId: primaryEliminatedId,
      eliminatedPlayerIds: sortedEliminated,
      publicMessage: publicMessage,
      mafiaTarget: mafiaTarget,
      doctorTarget: doctorTarget,
      bodyguardTarget: bodyguardTarget,
      bodyguardIntercepted: bodyguardIntercepted,
      vigilanteTarget: vigilanteTarget,
      vigilanteUsedAbility: vigilanteUsedAbility,
      detectiveResults: detectiveResults,
    );
  }

  /// Resolves the voting phase.
  ///
  /// Mechanism:
  /// - Counts votes per target.
  /// - The player with the highest vote count is eliminated.
  /// - If tied for highest, NO player is eliminated (returns null).
  static String? resolveVoteElimination(Map<String, String> votes) {
    if (votes.isEmpty) return null;

    final voteCounts = <String, int>{};
    for (final target in votes.values) {
      if (target.isEmpty || target == 'skip') continue;
      voteCounts[target] = (voteCounts[target] ?? 0) + 1;
    }

    if (voteCounts.isEmpty) return null;

    int maxVotes = 0;
    for (final count in voteCounts.values) {
      if (count > maxVotes) maxVotes = count;
    }

    final topTargets = voteCounts.entries
        .where((e) => e.value == maxVotes)
        .map((e) => e.key)
        .toList();

    // Tie check: if more than one player shares the highest vote count, no one is eliminated.
    if (topTargets.length > 1) {
      return null;
    }

    return topTargets.isNotEmpty ? topTargets.first : null;
  }

  /// Checks the win condition based on the living players list.
  ///
  /// Civilian team: Detective, Doctor, Bodyguard, Vigilante, Civilian.
  /// Mafia team: Mafia.
  ///
  /// [roleOverrides] allows the local simulation to supply private roles when
  /// [Player.role] is [PlayerRole.unknown] in the public player list.
  static WinCheckResult checkWinCondition(
    List<Player> livingPlayers, {
    Map<String, PlayerRole>? roleOverrides,
  }) {
    int mafiaCount = 0;
    int nonMafiaCount = 0;

    for (final p in livingPlayers) {
      if (p.isAlive) {
        final role = roleOverrides?[p.uid] ?? p.role;
        if (role == PlayerRole.mafia) {
          mafiaCount++;
        } else {
          nonMafiaCount++;
        }
      }
    }

    if (mafiaCount == 0) {
      return const WinCheckResult(
        isGameOver: true,
        winner: 'CIVILIANS',
        reason: 'All Mafia members have been eliminated! Civilians win!',
      );
    }

    if (mafiaCount >= nonMafiaCount) {
      return const WinCheckResult(
        isGameOver: true,
        winner: 'MAFIA',
        reason:
            'Mafia has reached numerical parity with Civilians! Mafia wins!',
      );
    }

    return const WinCheckResult(
      isGameOver: false,
      winner: null,
      reason: 'Game continues to next round.',
    );
  }
}

class ActionResolutionResult {
  final String? eliminatedPlayerId;
  final List<String> eliminatedPlayerIds;
  final String publicMessage;
  final String? mafiaTarget;
  final String? doctorTarget;
  final String? bodyguardTarget;
  final bool bodyguardIntercepted;
  final String? vigilanteTarget;
  final bool vigilanteUsedAbility;
  final Map<String, bool> detectiveResults; // detectiveUid -> isMafia

  const ActionResolutionResult({
    required this.eliminatedPlayerId,
    this.eliminatedPlayerIds = const [],
    required this.publicMessage,
    this.mafiaTarget,
    this.doctorTarget,
    this.bodyguardTarget,
    this.bodyguardIntercepted = false,
    this.vigilanteTarget,
    this.vigilanteUsedAbility = false,
    this.detectiveResults = const {},
  });
}

class WinCheckResult {
  final bool isGameOver;
  final String? winner; // 'CIVILIANS' or 'MAFIA'
  final String reason;

  const WinCheckResult({
    required this.isGameOver,
    required this.winner,
    required this.reason,
  });
}
