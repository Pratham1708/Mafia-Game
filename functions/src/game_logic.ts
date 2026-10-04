/**
 * game_logic.ts — Pure server-side Mafia game logic.
 *
 * Mirrors GameLogicEngine.dart but runs on the server in Cloud Functions,
 * ensuring all role assignments, action resolution, and win checking are
 * performed server-side and cannot be tampered with by any client.
 */

export type PlayerRole =
  | "mafia"
  | "detective"
  | "doctor"
  | "bodyguard"
  | "vigilante"
  | "civilian"
  | "unknown";

export interface RoleAssignment {
  [uid: string]: PlayerRole;
}

export interface ActionResolutionResult {
  eliminatedPlayerId: string | null;
  eliminatedPlayerIds: string[];
  publicMessage: string;
  mafiaTarget: string | null;
  doctorTarget: string | null;
  bodyguardTarget: string | null;
  bodyguardIntercepted: boolean;
  vigilanteTarget: string | null;
  vigilanteUsedAbility: boolean;
  detectiveResults: { [detectiveUid: string]: boolean }; // uid -> isMafia
}

export interface WinCheckResult {
  isGameOver: boolean;
  winner: "CIVILIANS" | "MAFIA" | null;
  reason: string;
}

/**
 * Returns the role distribution for a given player count (6-12).
 *
 * 6 players:  1 Mafia, 1 Detective, 1 Doctor, 0 Bodyguard, 0 Vigilante, 3 Civilians
 * 7 players:  2 Mafia, 1 Detective, 1 Doctor, 0 Bodyguard, 0 Vigilante, 3 Civilians
 * 8 players:  2 Mafia, 1 Detective, 1 Doctor, 0 Bodyguard, 0 Vigilante, 4 Civilians
 * 9 players:  2 Mafia, 1 Detective, 1 Doctor, 1 Bodyguard, 0 Vigilante, 4 Civilians
 * 10 players: 3 Mafia, 1 Detective, 1 Doctor, 1 Bodyguard, 0 Vigilante, 4 Civilians
 * 11 players: 3 Mafia, 1 Detective, 1 Doctor, 1 Bodyguard, 1 Vigilante, 4 Civilians
 * 12 players: 3 Mafia, 1 Detective, 1 Doctor, 1 Bodyguard, 1 Vigilante, 5 Civilians
 */
export function getRoleDistribution(playerCount: number): PlayerRole[] {
  if (playerCount < 6) {
    // Testing mode distribution for 4–5 players (covers all Phase 3 roles)
    const testRoles: PlayerRole[] = [
      "mafia",
      "detective",
      "doctor",
      ...(playerCount >= 4 ? ["bodyguard" as PlayerRole] : []),
      ...(playerCount >= 5 ? ["vigilante" as PlayerRole] : []),
    ];
    return testRoles.slice(0, playerCount);
  }

  let mafiaCount: number;
  const detectiveCount = 1;
  const doctorCount = 1;
  let bodyguardCount = 0;
  let vigilanteCount = 0;

  if (playerCount <= 6) {
    mafiaCount = 1;
  } else if (playerCount <= 9) {
    mafiaCount = 2;
    if (playerCount === 9) bodyguardCount = 1;
  } else {
    mafiaCount = 3;
    bodyguardCount = 1;
    if (playerCount >= 11) vigilanteCount = 1;
  }

  const civilianCount =
    playerCount -
    (mafiaCount + detectiveCount + doctorCount + bodyguardCount + vigilanteCount);

  const roles: PlayerRole[] = [
    ...Array(mafiaCount).fill("mafia"),
    ...Array(detectiveCount).fill("detective"),
    ...Array(doctorCount).fill("doctor"),
    ...(bodyguardCount > 0 ? Array(bodyguardCount).fill("bodyguard") : []),
    ...(vigilanteCount > 0 ? Array(vigilanteCount).fill("vigilante") : []),
    ...Array(civilianCount).fill("civilian"),
  ];

  return roles;
}

/**
 * Shuffles an array in-place using Fisher-Yates algorithm.
 */
function shuffleArray<T>(array: T[]): T[] {
  const arr = [...array];
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

/**
 * Assigns randomized roles to a list of player UIDs.
 */
export function assignRoles(playerUids: string[]): RoleAssignment {
  const roles = getRoleDistribution(playerUids.length);
  const shuffled = shuffleArray(roles);

  const assignments: RoleAssignment = {};
  for (let i = 0; i < playerUids.length; i++) {
    assignments[playerUids[i]] = shuffled[i];
  }
  return assignments;
}

/**
 * Resolves the Mafia's target using majority vote with alphabetical tie-breaking.
 */
export function resolveMafiaTarget(mafiaVotes: { [uid: string]: string }): string | null {
  const voteEntries = Object.values(mafiaVotes);
  if (voteEntries.length === 0) return null;

  const voteCounts: { [targetId: string]: number } = {};
  for (const target of voteEntries) {
    voteCounts[target] = (voteCounts[target] ?? 0) + 1;
  }

  const maxVotes = Math.max(...Object.values(voteCounts));
  const tied = Object.keys(voteCounts)
    .filter((k) => voteCounts[k] === maxVotes)
    .sort(); // deterministic tie-breaker

  return tied[0] ?? null;
}

/**
 * Resolves secret actions for a round with deterministic server authority.
 *
 * Order of resolution:
 * 1. Collect actions (Mafia, Doctor, Bodyguard, Vigilante, Detective)
 * 2. Resolve Mafia target
 * 3. Resolve Bodyguard interception:
 *    - If Mafia target == Bodyguard target: Bodyguard intercepts attack!
 *      Protected player survives Mafia strike.
 *      Bodyguard takes the lethal blow.
 * 4. Resolve Doctor protection:
 *    - Doctor shields doctorTarget from lethal attack this round.
 *    - If Doctor protected Bodyguard who intercepted: Bodyguard survives!
 *    - If Doctor protected Mafia target (not intercepted): target survives!
 *    - If Doctor protected Vigilante target: target survives!
 * 5. Resolve Vigilante attack:
 *    - One-time elimination. If used previously or target == doctorTarget, target survives.
 *    - Otherwise, target is eliminated.
 * 6. Resolve Detective investigations.
 * 7. Apply eliminations and return deterministic result.
 */
export function resolveSecretActions(params: {
  mafiaTarget: string | null;
  doctorTarget: string | null;
  bodyguardTarget?: string | null;
  bodyguardUid?: string | null;
  vigilanteTarget?: string | null;
  vigilanteUid?: string | null;
  vigilanteAlreadyUsed?: boolean;
  playerRoles: { [uid: string]: PlayerRole };
  detectiveTargets: { [detectiveUid: string]: string };
}): ActionResolutionResult {
  const {
    mafiaTarget,
    doctorTarget,
    bodyguardTarget,
    bodyguardUid,
    vigilanteTarget,
    vigilanteUid,
    vigilanteAlreadyUsed = false,
    playerRoles,
    detectiveTargets,
  } = params;

  const eliminatedUids = new Set<string>();
  let bodyguardIntercepted = false;
  let vigilanteUsedAbility = false;

  // 1 & 2. Mafia attack & Bodyguard interception
  if (mafiaTarget !== null) {
    if (
      bodyguardTarget !== null &&
      bodyguardTarget !== undefined &&
      bodyguardUid !== null &&
      bodyguardUid !== undefined &&
      bodyguardTarget === mafiaTarget &&
      bodyguardTarget !== bodyguardUid
    ) {
      bodyguardIntercepted = true;
      // Bodyguard takes the lethal blow unless healed by Doctor
      if (doctorTarget !== bodyguardUid) {
        eliminatedUids.add(bodyguardUid);
      }
    } else {
      // No interception: Doctor protection check
      if (doctorTarget !== mafiaTarget) {
        eliminatedUids.add(mafiaTarget);
      }
    }
  }

  // 3. Vigilante attack
  if (
    vigilanteTarget !== null &&
    vigilanteTarget !== undefined &&
    vigilanteTarget.length > 0 &&
    vigilanteTarget !== "skip" &&
    !vigilanteAlreadyUsed &&
    vigilanteUid !== null &&
    vigilanteUid !== undefined &&
    vigilanteTarget !== vigilanteUid
  ) {
    vigilanteUsedAbility = true;
    if (doctorTarget !== vigilanteTarget) {
      eliminatedUids.add(vigilanteTarget);
    }
  }

  // 4. Detective investigations
  const detectiveResults: { [uid: string]: boolean } = {};
  for (const [detectiveUid, targetUid] of Object.entries(detectiveTargets)) {
    detectiveResults[detectiveUid] = playerRoles[targetUid] === "mafia";
  }

  // Deterministically sort eliminated player UIDs
  const sortedEliminated = Array.from(eliminatedUids).sort();
  const primaryEliminatedId = sortedEliminated.length > 0 ? sortedEliminated[0] : null;

  let publicMessage: string;
  if (sortedEliminated.length === 0) {
    publicMessage = "No player was eliminated this round.";
  } else if (sortedEliminated.length === 1) {
    publicMessage = "A player was eliminated this round.";
  } else {
    publicMessage = `${sortedEliminated.length} players were eliminated this round.`;
  }

  return {
    eliminatedPlayerId: primaryEliminatedId,
    eliminatedPlayerIds: sortedEliminated,
    publicMessage,
    mafiaTarget,
    doctorTarget,
    bodyguardTarget: bodyguardTarget ?? null,
    bodyguardIntercepted,
    vigilanteTarget: vigilanteTarget ?? null,
    vigilanteUsedAbility,
    detectiveResults,
  };
}

/**
 * Resolves vote elimination using majority vote with alphabetical tie-breaking.
 */
export function resolveVoteElimination(votes: { [uid: string]: string }): string | null {
  const voteValues = Object.values(votes);
  if (voteValues.length === 0) return null;

  const voteCounts: { [targetId: string]: number } = {};
  for (const target of voteValues) {
    voteCounts[target] = (voteCounts[target] ?? 0) + 1;
  }

  const maxVotes = Math.max(...Object.values(voteCounts));
  const top = Object.keys(voteCounts)
    .filter((k) => voteCounts[k] === maxVotes)
    .sort();

  return top[0] ?? null;
}

/**
 * Checks win conditions based on living players.
 * - Mafia == 0 → Civilians win
 * - Mafia >= Non-Mafia → Mafia wins
 * - Otherwise → Game continues
 */
export function checkWinCondition(livingPlayers: Array<{ uid: string; role: PlayerRole }>): WinCheckResult {
  let mafiaCount = 0;
  let nonMafiaCount = 0;

  for (const p of livingPlayers) {
    if (p.role === "mafia") {
      mafiaCount++;
    } else {
      nonMafiaCount++;
    }
  }

  if (mafiaCount === 0) {
    return {
      isGameOver: true,
      winner: "CIVILIANS",
      reason: "All Mafia members have been eliminated! Civilians win!",
    };
  }

  if (mafiaCount >= nonMafiaCount) {
    return {
      isGameOver: true,
      winner: "MAFIA",
      reason: "Mafia has reached numerical parity with Civilians! Mafia wins!",
    };
  }

  return {
    isGameOver: false,
    winner: null,
    reason: "Game continues to next round.",
  };
}

/** Returns true if the role requires a secret action. */
export function roleHasSecretAction(role: PlayerRole): boolean {
  return (
    role === "mafia" ||
    role === "detective" ||
    role === "doctor" ||
    role === "bodyguard" ||
    role === "vigilante"
  );
}

