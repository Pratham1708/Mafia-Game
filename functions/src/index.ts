/**
 * Mafia Multiplayer — Cloud Functions (Phase 2 + Read Isolation)
 *
 * Private data architecture:
 *   roles      → rooms/{roomId}/privatePlayerData/{uid}          (owner-read)
 *   actions    → rooms/{roomId}/rounds/{N}/privateActions/{uid}  (owner-read)
 *   votes      → rooms/{roomId}/rounds/{N}/privateVotes/{uid}    (owner-read)
 *   det result → rooms/{roomId}/rounds/{N}/privateResults/{uid}  (owner-read)
 *
 * Public data:
 *   room doc   → status, phase, currentRound, winner, eliminatedThisRound
 *   player doc → uid, name, isAlive, isHost, isBot, joinedAt  (NO role during PLAYING)
 *                role written here ONLY at GAME_OVER for reveal screen
 *   round doc  → actionsCount, votesCount, actionsResolved,
 *                votesResolved, eliminatedInActions, eliminatedInVote
 *
 * Functions:
 *   startGame          — assigns roles → privatePlayerData
 *   advanceToActions   — transitions phase
 *   submitAction       — writes to privateActions, increments actionsCount
 *   submitVote         — writes to privateVotes, increments votesCount
 *   advanceToVoting    — transitions phase
 *   advanceToNextRound — win check then advance
 *   triggerBotActions  — host-only: server generates bot secret actions
 *   triggerBotVotes    — host-only: server generates bot votes
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import {
  assignRoles,
  resolveSecretActions,
  resolveVoteElimination,
  checkWinCondition,
  resolveMafiaTarget,
  roleHasSecretAction,
  PlayerRole,
} from "./game_logic";

if (!admin.apps.length) {
  admin.initializeApp();
}
const db = admin.firestore();

/**
 * Temporary testing mode flag for Cloud Functions.
 * When true: allows 4–5 player rooms (MIN_PLAYERS = 4).
 * When false: enforces production 6–12 player rooms (MIN_PLAYERS = 6).
 */
export const TESTING_MODE = true;
const MIN_PLAYERS = TESTING_MODE ? 4 : 6;

// ─── Type Helpers ─────────────────────────────────────────────────────────────

function assertAuth(auth: { uid: string } | undefined): string {
  if (!auth?.uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return auth.uid;
}

function assertString(val: unknown, field: string): string {
  if (typeof val !== "string" || val.trim().length === 0) {
    throw new HttpsError("invalid-argument", `${field} must be a non-empty string.`);
  }
  return val.trim();
}

function assertNumber(val: unknown, field: string): number {
  if (typeof val !== "number") {
    throw new HttpsError("invalid-argument", `${field} must be a number.`);
  }
  return val;
}

interface PlayerDoc {
  uid: string;
  name: string;
  isAlive: boolean;
  isHost: boolean;
  isBot: boolean;
}

// ─── Room/Host Helpers ────────────────────────────────────────────────────────

async function getRoomAndAssertHost(roomId: string, uid: string) {
  const roomRef = db.collection("rooms").doc(roomId);
  const roomSnap = await roomRef.get();
  if (!roomSnap.exists) throw new HttpsError("not-found", "Room not found.");
  const roomData = roomSnap.data()!;
  if (roomData.hostId !== uid) {
    throw new HttpsError("permission-denied", "Only the host can perform this action.");
  }
  return { roomRef, roomData };
}

async function getPublicPlayers(roomRef: admin.firestore.DocumentReference): Promise<PlayerDoc[]> {
  const snap = await roomRef.collection("players").get();
  return snap.docs.map((d) => ({ ...d.data(), uid: d.id } as PlayerDoc));
}

async function getPlayerRole(
  roomRef: admin.firestore.DocumentReference,
  uid: string
): Promise<PlayerRole> {
  const snap = await roomRef.collection("privatePlayerData").doc(uid).get();
  if (!snap.exists) return "civilian";
  return (snap.data()!.role as PlayerRole) ?? "civilian";
}

// ─── startGame ───────────────────────────────────────────────────────────────

export const startGame = onCall(
  { region: "asia-south1", enforceAppCheck: false },
  async (request) => {
    try {
      const uid = assertAuth(request.auth);
      const roomId = assertString(request.data?.roomId, "roomId");

      const { roomRef, roomData } = await getRoomAndAssertHost(roomId, uid);

      if (roomData.status === "GAME_OVER") {
        throw new HttpsError("failed-precondition", "This game has already ended.");
      }
      if (roomData.status !== "LOBBY") {
        throw new HttpsError("failed-precondition", "Game has already started.");
      }

      const players = await getPublicPlayers(roomRef);
      if (players.length < MIN_PLAYERS) {
        throw new HttpsError("failed-precondition", `At least ${MIN_PLAYERS} players are required to start.`);
      }
      if (players.length > 12) {
        throw new HttpsError("failed-precondition", "Maximum 12 players allowed.");
      }

      console.log(`[startGame] roomId=${roomId} players=${players.length} uids=${players.map((p) => p.uid).join(",")}`);

      const playerUids = players.map((p) => p.uid);
      const assignments = assignRoles(playerUids);

      const batch = db.batch();

      // Write each player's role to privatePlayerData/{uid} — NOT to the public player doc.
      for (const player of players) {
        const role = assignments[player.uid] ?? "civilian";
        console.log(`[startGame] assigning role=${role} to uid=${player.uid}`);
        batch.set(roomRef.collection("privatePlayerData").doc(player.uid), { role });
        // Ensure isAlive is set on the public player doc (no role here)
        batch.set(roomRef.collection("players").doc(player.uid), { isAlive: true }, { merge: true });
      }

      // Initialize public Round 1 document (no private data)
      const round1Ref = roomRef.collection("rounds").doc("1");
      batch.set(round1Ref, {
        roundNumber: 1,
        actionsCount: 0,
        votesCount: 0,
        eliminatedInActions: null,
        eliminatedInVote: null,
        actionsResolved: false,
        votesResolved: false,
      });

      // Transition room to PLAYING
      batch.update(roomRef, {
        status: "PLAYING",
        currentRound: 1,
        currentPhase: "roleReveal",
        publicMessage: "Game started! Memorize your secret role.",
        startedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await batch.commit();
      console.log(`[startGame] SUCCESS roomId=${roomId}`);
      return { success: true };
    } catch (err) {
      // Re-throw HttpsErrors as-is; wrap unknown errors with details for logging
      if (err instanceof HttpsError) throw err;
      console.error("[startGame] UNEXPECTED ERROR:", err);
      throw new HttpsError("unknown", `startGame failed: ${(err as Error).message ?? String(err)}`);
    }
  }
);

// ─── advanceToActions ────────────────────────────────────────────────────────

export const advanceToActions = onCall(
  { region: "asia-south1", enforceAppCheck: false },
  async (request) => {
    const uid = assertAuth(request.auth);
    const roomId = assertString(request.data?.roomId, "roomId");

    const { roomRef, roomData } = await getRoomAndAssertHost(roomId, uid);

    if (!["roleReveal"].includes(roomData.currentPhase)) {
      throw new HttpsError(
        "failed-precondition",
        `Cannot advance to actions from phase: ${roomData.currentPhase}`
      );
    }

    await roomRef.update({
      currentPhase: "actions",
      publicMessage: "Secret actions in progress. Choose your targets carefully.",
    });

    return { success: true };
  }
);

// ─── submitAction ─────────────────────────────────────────────────────────────

export const submitAction = onCall(
  { region: "asia-south1", enforceAppCheck: false },
  async (request) => {
    const uid = assertAuth(request.auth);
    const roomId = assertString(request.data?.roomId, "roomId");
    const roundNumber = assertNumber(request.data?.roundNumber, "roundNumber");
    const rawTargetId = request.data?.targetId;
    const targetId = typeof rawTargetId === "string" ? rawTargetId.trim() : "";

    const roomRef = db.collection("rooms").doc(roomId);
    const roundRef = roomRef.collection("rounds").doc(String(roundNumber));
    const privateActionRef = roundRef.collection("privateActions").doc(uid);

    // Validate in a transaction to prevent races
    await db.runTransaction(async (tx) => {
      const [roomSnap, playerSnap, privateRoleSnap, roundSnap, existingActionSnap] =
        await Promise.all([
          tx.get(roomRef),
          tx.get(roomRef.collection("players").doc(uid)),
          tx.get(roomRef.collection("privatePlayerData").doc(uid)),
          tx.get(roundRef),
          tx.get(privateActionRef),
        ]);

      if (!roomSnap.exists) throw new HttpsError("not-found", "Room not found.");
      const roomData = roomSnap.data()!;
      if (roomData.currentPhase !== "actions") {
        throw new HttpsError("failed-precondition", "Secret actions phase is not active.");
      }
      if (roomData.currentRound !== roundNumber) {
        throw new HttpsError("failed-precondition", "Round number mismatch.");
      }

      if (!playerSnap.exists) throw new HttpsError("not-found", "Player not found in room.");
      const player = playerSnap.data() as PlayerDoc;
      if (!player.isAlive) {
        throw new HttpsError("permission-denied", "Dead players cannot submit actions.");
      }

      // Read role from private document
      if (!privateRoleSnap.exists) {
        throw new HttpsError("not-found", "Private role data not found.");
      }
      const roleData = privateRoleSnap.data()!;
      const role = (roleData.role as PlayerRole) ?? "civilian";
      const hasUsedAbility = (roleData.hasUsedAbility as boolean) ?? false;

      if (!roleHasSecretAction(role)) {
        throw new HttpsError("permission-denied", "Your role does not have a secret action.");
      }

      // Check Vigilante ability consumption
      if (role === "vigilante" && hasUsedAbility) {
        throw new HttpsError("permission-denied", "Vigilante has already used their one-time ability.");
      }

      // Vigilante can choose to skip / hold fire
      const isSkip = role === "vigilante" && (targetId === "" || targetId === "skip");

      if (!isSkip) {
        if (!targetId) {
          throw new HttpsError("invalid-argument", "targetId must be specified.");
        }

        const targetSnap = await tx.get(roomRef.collection("players").doc(targetId));
        if (!targetSnap.exists || !(targetSnap.data() as PlayerDoc).isAlive) {
          throw new HttpsError("invalid-argument", "Target player not found or already eliminated.");
        }

        if ((role === "mafia" || role === "detective" || role === "bodyguard" || role === "vigilante") && targetId === uid) {
          throw new HttpsError("invalid-argument", "You cannot target yourself.");
        }
      }

      if (!roundSnap.exists) throw new HttpsError("not-found", "Round document not found.");
      if (roundSnap.data()!.actionsResolved) {
        throw new HttpsError("failed-precondition", "Actions already resolved.");
      }

      // Idempotency: ignore duplicate submissions
      if (existingActionSnap.exists) return;

      // Write private action to owner-only subcollection
      tx.set(privateActionRef, { targetId: isSkip ? "skip" : targetId, role });

      // Increment public actionsCount (no details)
      tx.update(roundRef, {
        actionsCount: admin.firestore.FieldValue.increment(1),
      });
    });

    await _maybeResolveActions(roomRef, roundRef, roundNumber);
    return { success: true };
  }
);

// ─── submitVote ───────────────────────────────────────────────────────────────

export const submitVote = onCall(
  { region: "asia-south1", enforceAppCheck: false },
  async (request) => {
    const uid = assertAuth(request.auth);
    const roomId = assertString(request.data?.roomId, "roomId");
    const roundNumber = assertNumber(request.data?.roundNumber, "roundNumber");
    const targetId = assertString(request.data?.targetId, "targetId");

    const roomRef = db.collection("rooms").doc(roomId);
    const roundRef = roomRef.collection("rounds").doc(String(roundNumber));
    const privateVoteRef = roundRef.collection("privateVotes").doc(uid);

    await db.runTransaction(async (tx) => {
      const [roomSnap, voterSnap, targetSnap, roundSnap, existingVoteSnap] = await Promise.all([
        tx.get(roomRef),
        tx.get(roomRef.collection("players").doc(uid)),
        tx.get(roomRef.collection("players").doc(targetId)),
        tx.get(roundRef),
        tx.get(privateVoteRef),
      ]);

      if (!roomSnap.exists) throw new HttpsError("not-found", "Room not found.");
      const roomData = roomSnap.data()!;
      if (roomData.currentPhase !== "voting") {
        throw new HttpsError("failed-precondition", "Voting phase is not active.");
      }
      if (roomData.currentRound !== roundNumber) {
        throw new HttpsError("failed-precondition", "Round number mismatch.");
      }

      if (!voterSnap.exists) throw new HttpsError("not-found", "Player not found in room.");
      const voter = voterSnap.data() as PlayerDoc;
      if (!voter.isAlive) {
        throw new HttpsError("permission-denied", "Dead players cannot vote.");
      }

      if (!targetSnap.exists || !(targetSnap.data() as PlayerDoc).isAlive) {
        throw new HttpsError("invalid-argument", "Vote target is not a living player.");
      }
      if (targetId === uid) {
        throw new HttpsError("invalid-argument", "You cannot vote for yourself.");
      }

      if (!roundSnap.exists) throw new HttpsError("not-found", "Round not found.");
      if (roundSnap.data()!.votesResolved) {
        throw new HttpsError("failed-precondition", "Voting is already resolved.");
      }

      if (existingVoteSnap.exists) return; // idempotent

      // Write private vote to owner-only subcollection
      tx.set(privateVoteRef, { targetId });

      // Increment public votesCount (no details)
      tx.update(roundRef, {
        votesCount: admin.firestore.FieldValue.increment(1),
      });
    });

    await _maybeResolveVotes(roomRef, roundRef, roundNumber);
    return { success: true };
  }
);

// ─── advanceToDiscussion ─────────────────────────────────────────────────────

export const advanceToDiscussion = onCall(
  { region: "asia-south1", enforceAppCheck: false },
  async (request) => {
    const uid = assertAuth(request.auth);
    const roomId = assertString(request.data?.roomId, "roomId");

    const { roomRef, roomData } = await getRoomAndAssertHost(roomId, uid);

    if (roomData.currentPhase !== "roundResult") {
      throw new HttpsError(
        "failed-precondition",
        `Cannot advance to discussion from phase: ${roomData.currentPhase}`
      );
    }

    const durationSeconds = 60;
    const endTimestamp = admin.firestore.Timestamp.fromMillis(Date.now() + durationSeconds * 1000);

    await roomRef.update({
      currentPhase: "discussion",
      discussionEndTimestamp: endTimestamp,
      discussionDurationSeconds: durationSeconds,
      publicMessage: "Discussion phase. Discuss with your fellow players.",
    });

    return { success: true, discussionEndTimestamp: endTimestamp.toMillis() };
  }
);

// ─── advanceToVoting ──────────────────────────────────────────────────────────

export const advanceToVoting = onCall(
  { region: "asia-south1", enforceAppCheck: false },
  async (request) => {
    const uid = assertAuth(request.auth);
    const roomId = assertString(request.data?.roomId, "roomId");

    const { roomRef, roomData } = await getRoomAndAssertHost(roomId, uid);

    if (!["roundResult", "discussion"].includes(roomData.currentPhase)) {
      throw new HttpsError(
        "failed-precondition",
        `Cannot advance to voting from phase: ${roomData.currentPhase}`
      );
    }

    await roomRef.update({
      currentPhase: "voting",
      publicMessage: "Discussion and voting. Who is the Mafia?",
    });

    return { success: true };
  }
);

// ─── advanceToNextRound ───────────────────────────────────────────────────────

export const advanceToNextRound = onCall(
  { region: "asia-south1", enforceAppCheck: false },
  async (request) => {
    const uid = assertAuth(request.auth);
    const roomId = assertString(request.data?.roomId, "roomId");

    const { roomRef, roomData } = await getRoomAndAssertHost(roomId, uid);

    const allowedPhases = ["elimination", "roundResult"];
    if (!allowedPhases.includes(roomData.currentPhase)) {
      throw new HttpsError(
        "failed-precondition",
        `Cannot advance round from phase: ${roomData.currentPhase}`
      );
    }

    const players = await getPublicPlayers(roomRef);
    const livingPlayers = players.filter((p) => p.isAlive);
    const livingRoles = await Promise.all(
      livingPlayers.map(async (p) => ({
        uid: p.uid,
        role: await getPlayerRole(roomRef, p.uid),
      }))
    );
    const winCheck = checkWinCondition(livingRoles);

    if (winCheck.isGameOver) {
      // At GAME_OVER: write each player's real role to the public player doc for the reveal screen.
      const batch = db.batch();
      for (const p of players) {
        const role = await getPlayerRole(roomRef, p.uid);
        batch.update(roomRef.collection("players").doc(p.uid), { role });
      }
      batch.update(roomRef, {
        status: "GAME_OVER",
        currentPhase: "gameOver",
        winner: winCheck.winner,
        publicMessage: winCheck.reason,
      });
      await batch.commit();
      return { success: true, isGameOver: true, winner: winCheck.winner };
    }

    const nextRound = (roomData.currentRound as number) + 1;
    const nextRoundRef = roomRef.collection("rounds").doc(String(nextRound));

    const batch = db.batch();
    batch.set(nextRoundRef, {
      roundNumber: nextRound,
      actionsCount: 0,
      votesCount: 0,
      eliminatedInActions: null,
      eliminatedInVote: null,
      actionsResolved: false,
      votesResolved: false,
    });
    batch.update(roomRef, {
      currentRound: nextRound,
      currentPhase: "actions",
      eliminatedThisRound: null,
      votedOutThisRound: null,
      publicMessage: `Round ${nextRound}: Secret actions in progress.`,
    });

    await batch.commit();
    return { success: true, isGameOver: false };
  }
);

// ─── triggerBotActions (host-only) ───────────────────────────────────────────

export const triggerBotActions = onCall(
  { region: "asia-south1", enforceAppCheck: false },
  async (request) => {
    const uid = assertAuth(request.auth);
    const roomId = assertString(request.data?.roomId, "roomId");

    const { roomRef, roomData } = await getRoomAndAssertHost(roomId, uid);

    if (roomData.currentPhase !== "actions") {
      throw new HttpsError("failed-precondition", "Not in actions phase.");
    }

    const roundNumber = roomData.currentRound as number;
    const roundRef = roomRef.collection("rounds").doc(String(roundNumber));

    const [playersSnap, roundSnap] = await Promise.all([
      roomRef.collection("players").get(),
      roundRef.get(),
    ]);

    if (!roundSnap.exists || roundSnap.data()!.actionsResolved) return { success: true };

    const players = playersSnap.docs.map((d) => ({ uid: d.id, ...d.data() } as PlayerDoc));
    const livingPlayers = players.filter((p) => p.isAlive);
    const livingBots = livingPlayers.filter((p) => p.isBot);

    if (livingBots.length === 0) return { success: true };

    // Read all bot roles from privatePlayerData
    const botRoles = await Promise.all(
      livingBots.map(async (b) => ({
        uid: b.uid,
        role: await getPlayerRole(roomRef, b.uid),
      }))
    );

    const batch = db.batch();
    let actionsAdded = 0;

    for (const botRole of botRoles) {
      if (!roleHasSecretAction(botRole.role)) continue;

      const existingSnap = await roundRef.collection("privateActions").doc(botRole.uid).get();
      if (existingSnap.exists) continue;

      // Pick a random valid target
      let validTargets: PlayerDoc[];
      if (
        botRole.role === "detective" ||
        botRole.role === "mafia" ||
        botRole.role === "bodyguard"
      ) {
        validTargets = livingPlayers.filter((p) => p.uid !== botRole.uid);
      } else if (botRole.role === "vigilante") {
        const privSnap = await roomRef.collection("privatePlayerData").doc(botRole.uid).get();
        const hasUsed = privSnap.exists && privSnap.data()!.hasUsedAbility === true;
        if (hasUsed) continue;
        // Vigilante bot has 30% chance to shoot, otherwise holds fire
        if (Math.random() < 0.3) {
          validTargets = livingPlayers.filter((p) => p.uid !== botRole.uid);
        } else {
          batch.set(roundRef.collection("privateActions").doc(botRole.uid), {
            targetId: "skip",
            role: botRole.role,
          });
          batch.update(roundRef, {
            actionsCount: admin.firestore.FieldValue.increment(1),
          });
          actionsAdded++;
          continue;
        }
      } else {
        // Doctor can protect any living player including self
        validTargets = livingPlayers;
      }

      if (validTargets.length === 0) continue;

      const target = validTargets[Math.floor(Math.random() * validTargets.length)];
      batch.set(roundRef.collection("privateActions").doc(botRole.uid), {
        targetId: target.uid,
        role: botRole.role,
      });
      batch.update(roundRef, {
        actionsCount: admin.firestore.FieldValue.increment(1),
      });
      actionsAdded++;
    }

    if (actionsAdded > 0) {
      await batch.commit();
    }

    // Trigger resolution check
    await _maybeResolveActions(roomRef, roundRef, roundNumber);
    return { success: true };
  }
);

// ─── triggerBotVotes (host-only) ─────────────────────────────────────────────

export const triggerBotVotes = onCall(
  { region: "asia-south1", enforceAppCheck: false },
  async (request) => {
    const uid = assertAuth(request.auth);
    const roomId = assertString(request.data?.roomId, "roomId");

    const { roomRef, roomData } = await getRoomAndAssertHost(roomId, uid);

    if (roomData.currentPhase !== "voting") {
      throw new HttpsError("failed-precondition", "Not in voting phase.");
    }

    const roundNumber = roomData.currentRound as number;
    const roundRef = roomRef.collection("rounds").doc(String(roundNumber));

    const [playersSnap, roundSnap] = await Promise.all([
      roomRef.collection("players").get(),
      roundRef.get(),
    ]);

    if (!roundSnap.exists || roundSnap.data()!.votesResolved) return { success: true };

    const players = playersSnap.docs.map((d) => ({ uid: d.id, ...d.data() } as PlayerDoc));
    const livingPlayers = players.filter((p) => p.isAlive);
    const livingBots = livingPlayers.filter((p) => p.isBot);

    if (livingBots.length === 0) return { success: true };

    const batch = db.batch();
    let votesAdded = 0;

    for (const bot of livingBots) {
      const existingSnap = await roundRef.collection("privateVotes").doc(bot.uid).get();
      if (existingSnap.exists) continue;

      const candidates = livingPlayers.filter((p) => p.uid !== bot.uid);
      if (candidates.length === 0) continue;

      const target = candidates[Math.floor(Math.random() * candidates.length)];
      batch.set(roundRef.collection("privateVotes").doc(bot.uid), {
        targetId: target.uid,
      });
      batch.update(roundRef, {
        votesCount: admin.firestore.FieldValue.increment(1),
      });
      votesAdded++;
    }

    if (votesAdded > 0) {
      await batch.commit();
    }

    await _maybeResolveVotes(roomRef, roundRef, roundNumber);
    return { success: true };
  }
);

// ─── Internal: _maybeResolveActions ──────────────────────────────────────────

async function _maybeResolveActions(
  roomRef: admin.firestore.DocumentReference,
  roundRef: admin.firestore.DocumentReference,
  roundNumber: number
) {
  const [playersSnap, roundSnap] = await Promise.all([
    roomRef.collection("players").get(),
    roundRef.get(),
  ]);

  const players = playersSnap.docs.map((d) => ({ uid: d.id, ...d.data() } as PlayerDoc));
  const roundData = roundSnap.data()!;

  if (roundData.actionsResolved) return;

  const livingPlayers = players.filter((p) => p.isAlive);

  // Find players that need to submit actions (those with special roles)
  const livingSpecialRoles: { uid: string; role: PlayerRole }[] = [];
  for (const p of livingPlayers) {
    const role = await getPlayerRole(roomRef, p.uid);
    if (roleHasSecretAction(role)) {
      if (role === "vigilante") {
        const vigSnap = await roomRef.collection("privatePlayerData").doc(p.uid).get();
        if (vigSnap.exists && vigSnap.data()!.hasUsedAbility === true) {
          continue;
        }
      }
      livingSpecialRoles.push({ uid: p.uid, role });
    }
  }

  // Check whether all required actions are submitted
  const submittedSnap = await roundRef.collection("privateActions").get();
  const submittedUids = new Set(submittedSnap.docs.map((d) => d.id));

  const allSubmitted = livingSpecialRoles.every((p) => submittedUids.has(p.uid));
  if (!allSubmitted) return;

  // Tally submitted actions
  const mafiaVotes: { [uid: string]: string } = {};
  let doctorTarget: string | null = null;
  const detectiveTargets: { [uid: string]: string } = {};
  let bodyguardTarget: string | null = null;
  let bodyguardUid: string | null = null;
  let vigilanteTarget: string | null = null;
  let vigilanteUid: string | null = null;
  let vigilanteAlreadyUsed = false;

  for (const doc of submittedSnap.docs) {
    const data = doc.data();
    const actorRole = data.role as PlayerRole;
    const targetId = data.targetId as string;
    if (actorRole === "mafia") {
      mafiaVotes[doc.id] = targetId;
    } else if (actorRole === "doctor") {
      doctorTarget = targetId;
    } else if (actorRole === "detective") {
      detectiveTargets[doc.id] = targetId;
    } else if (actorRole === "bodyguard") {
      bodyguardTarget = targetId;
      bodyguardUid = doc.id;
    } else if (actorRole === "vigilante") {
      vigilanteTarget = targetId;
      vigilanteUid = doc.id;
    }
  }

  if (vigilanteUid) {
    const vigSnap = await roomRef.collection("privatePlayerData").doc(vigilanteUid).get();
    if (vigSnap.exists && vigSnap.data()!.hasUsedAbility === true) {
      vigilanteAlreadyUsed = true;
    }
  }

  // Build role map for resolution (from privatePlayerData)
  const playerRoles: { [uid: string]: PlayerRole } = {};
  for (const p of players) {
    playerRoles[p.uid] = await getPlayerRole(roomRef, p.uid);
  }

  const mafiaTarget = resolveMafiaTarget(mafiaVotes);
  const result = resolveSecretActions({
    mafiaTarget,
    doctorTarget,
    bodyguardTarget,
    bodyguardUid,
    vigilanteTarget,
    vigilanteUid,
    vigilanteAlreadyUsed,
    playerRoles,
    detectiveTargets,
  });

  const batch = db.batch();

  // If vigilante used ability, consume it on privatePlayerData
  if (result.vigilanteUsedAbility && vigilanteUid) {
    batch.update(roomRef.collection("privatePlayerData").doc(vigilanteUid), {
      hasUsedAbility: true,
    });
  }

  // Mark all eliminated players in public player doc
  for (const elimUid of result.eliminatedPlayerIds) {
    batch.update(roomRef.collection("players").doc(elimUid), {
      isAlive: false,
    });
  }

  // Write Detective investigation result to PRIVATE subcollection (owner-read only)
  for (const [detectiveUid, isMafia] of Object.entries(result.detectiveResults)) {
    const privateResultRef = roundRef.collection("privateResults").doc(detectiveUid);
    batch.set(privateResultRef, {
      targetId: detectiveTargets[detectiveUid],
      isMafia,
    });
  }

  // Update public round doc: public summary only
  batch.update(roundRef, {
    actionsResolved: true,
    eliminatedInActions: result.eliminatedPlayerId ?? null,
    eliminatedPlayerIds: result.eliminatedPlayerIds,
  });

  // Win check
  const updatedLiving = livingPlayers
    .filter((p) => !result.eliminatedPlayerIds.includes(p.uid))
    .map((p) => ({ uid: p.uid, role: playerRoles[p.uid] ?? "civilian" }));
  const winCheck = checkWinCondition(updatedLiving);

  if (winCheck.isGameOver) {
    // Reveal roles at game over: write to public player doc
    for (const p of players) {
      batch.update(roomRef.collection("players").doc(p.uid), {
        role: playerRoles[p.uid] ?? "civilian",
      });
    }
    batch.update(roomRef, {
      status: "GAME_OVER",
      currentPhase: "gameOver",
      winner: winCheck.winner,
      eliminatedThisRound: result.eliminatedPlayerId ?? null,
      publicMessage: `${result.publicMessage} ${winCheck.reason}`,
    });
  } else {
    batch.update(roomRef, {
      currentPhase: "roundResult",
      eliminatedThisRound: result.eliminatedPlayerId ?? null,
      publicMessage: result.publicMessage,
    });
  }

  await batch.commit();
}

// ─── Realtime Chat Callables ──────────────────────────────────────────────────

export const sendMessage = onCall(
  { region: "asia-south1", enforceAppCheck: false },
  async (request) => {
    const uid = assertAuth(request.auth);
    const roomId = assertString(request.data?.roomId, "roomId");
    const rawMessage = assertString(request.data?.message, "message");
    const message = rawMessage.trim();

    if (message.length === 0 || message.length > 500) {
      throw new HttpsError("invalid-argument", "Message must be between 1 and 500 characters.");
    }

    const roomRef = db.collection("rooms").doc(roomId);
    const [roomSnap, playerSnap] = await Promise.all([
      roomRef.get(),
      roomRef.collection("players").doc(uid).get(),
    ]);

    if (!roomSnap.exists) throw new HttpsError("not-found", "Room not found.");
    const roomData = roomSnap.data()!;
    if (roomData.currentPhase !== "discussion") {
      throw new HttpsError("failed-precondition", "Discussion chat is only open during the discussion phase.");
    }

    if (!playerSnap.exists) throw new HttpsError("permission-denied", "You are not a member of this room.");
    const player = playerSnap.data() as PlayerDoc;
    if (!player.isAlive) {
      throw new HttpsError("permission-denied", "Eliminated players cannot participate in discussion.");
    }

    const messageRef = roomRef.collection("messages").doc();
    await messageRef.set({
      messageId: messageRef.id,
      senderId: uid,
      senderName: player.name,
      message,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      isSpectator: false,
    });

    return { success: true, messageId: messageRef.id };
  }
);

export const sendSpectatorMessage = onCall(
  { region: "asia-south1", enforceAppCheck: false },
  async (request) => {
    const uid = assertAuth(request.auth);
    const roomId = assertString(request.data?.roomId, "roomId");
    const rawMessage = assertString(request.data?.message, "message");
    const message = rawMessage.trim();

    if (message.length === 0 || message.length > 500) {
      throw new HttpsError("invalid-argument", "Message must be between 1 and 500 characters.");
    }

    const roomRef = db.collection("rooms").doc(roomId);
    const [roomSnap, playerSnap] = await Promise.all([
      roomRef.get(),
      roomRef.collection("players").doc(uid).get(),
    ]);

    if (!roomSnap.exists) throw new HttpsError("not-found", "Room not found.");
    if (!playerSnap.exists) throw new HttpsError("permission-denied", "You are not a member of this room.");
    const player = playerSnap.data() as PlayerDoc;
    if (player.isAlive) {
      throw new HttpsError("permission-denied", "Living players cannot send spectator messages.");
    }

    const msgRef = roomRef.collection("spectatorMessages").doc();
    await msgRef.set({
      messageId: msgRef.id,
      senderId: uid,
      senderName: player.name,
      message,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      isSpectator: true,
    });

    return { success: true, messageId: msgRef.id };
  }
);

// ─── Internal: _maybeResolveVotes ────────────────────────────────────────────

async function _maybeResolveVotes(
  roomRef: admin.firestore.DocumentReference,
  roundRef: admin.firestore.DocumentReference,
  roundNumber: number
) {
  const [playersSnap, roundSnap] = await Promise.all([
    roomRef.collection("players").get(),
    roundRef.get(),
  ]);

  const players = playersSnap.docs.map((d) => ({ uid: d.id, ...d.data() } as PlayerDoc));
  const roundData = roundSnap.data()!;

  if (roundData.votesResolved) return;

  const livingPlayers = players.filter((p) => p.isAlive);

  // Check if all living players have voted
  const submittedSnap = await roundRef.collection("privateVotes").get();
  const submittedVoterUids = submittedSnap.docs.map((d) => d.id);
  const livingUids = new Set(livingPlayers.map((p) => p.uid));
  const allVoted = livingPlayers.every((p) => submittedVoterUids.includes(p.uid));
  if (!allVoted) {
    void livingUids; // suppress unused var
    return;
  }

  // Tally votes
  const votesFlat: { [uid: string]: string } = {};
  for (const doc of submittedSnap.docs) {
    if (livingUids.has(doc.id)) {
      votesFlat[doc.id] = doc.data().targetId as string;
    }
  }

  const eliminatedUid = resolveVoteElimination(votesFlat);
  const eliminatedPlayer = players.find((p) => p.uid === eliminatedUid);

  const batch = db.batch();

  if (eliminatedUid) {
    batch.update(roomRef.collection("players").doc(eliminatedUid), { isAlive: false });
  }

  batch.update(roundRef, {
    votesResolved: true,
    eliminatedInVote: eliminatedUid ?? null,
  });

  // Win check
  const updatedLiving = livingPlayers.filter((p) => p.uid !== eliminatedUid);
  const livingRoles = await Promise.all(
    updatedLiving.map(async (p) => ({
      uid: p.uid,
      role: await getPlayerRole(roomRef, p.uid),
    }))
  );
  const winCheck = checkWinCondition(livingRoles);

  if (winCheck.isGameOver) {
    // Reveal roles
    const allRoles: { [uid: string]: PlayerRole } = {};
    for (const p of players) {
      allRoles[p.uid] = await getPlayerRole(roomRef, p.uid);
    }
    for (const p of players) {
      batch.update(roomRef.collection("players").doc(p.uid), { role: allRoles[p.uid] });
    }
    batch.update(roomRef, {
      status: "GAME_OVER",
      currentPhase: "gameOver",
      winner: winCheck.winner,
      votedOutThisRound: eliminatedUid ?? null,
      publicMessage: `${eliminatedPlayer?.name ?? "A player"} was eliminated by vote. ${winCheck.reason}`,
    });
  } else {
    batch.update(roomRef, {
      currentPhase: "elimination",
      votedOutThisRound: eliminatedUid ?? null,
      publicMessage: `${eliminatedPlayer?.name ?? "A player"} was eliminated by vote.`,
    });
  }

  await batch.commit();
  void roundNumber;
}

// ─── claimHost ───────────────────────────────────────────────────────────────

export const claimHost = onCall(
  { region: "asia-south1", enforceAppCheck: false },
  async (request) => {
    const uid = assertAuth(request.auth);
    const roomId = assertString(request.data?.roomId, "roomId");

    const roomRef = db.collection("rooms").doc(roomId);
    const roomSnap = await roomRef.get();
    if (!roomSnap.exists) throw new HttpsError("not-found", "Room not found.");
    const roomData = roomSnap.data()!;

    if (roomData.status === "GAME_OVER") {
      throw new HttpsError("failed-precondition", "Cannot change host after game over.");
    }

    const playerSnap = await roomRef.collection("players").doc(uid).get();
    if (!playerSnap.exists) {
      throw new HttpsError("permission-denied", "You are not a member of this room.");
    }
    const playerData = playerSnap.data() as PlayerDoc;
    if (!playerData.isAlive) {
      throw new HttpsError("permission-denied", "Eliminated players cannot claim host.");
    }

    const currentHostId = roomData.hostId as string;
    if (currentHostId === uid) {
      return { success: true, hostId: uid };
    }

    const batch = db.batch();
    batch.update(roomRef, {
      hostId: uid,
      publicMessage: `${playerData.name} has taken over as room host.`,
    });
    batch.update(roomRef.collection("players").doc(uid), { isHost: true });

    // If previous host doc exists in players, unset isHost
    const oldHostSnap = await roomRef.collection("players").doc(currentHostId).get();
    if (oldHostSnap.exists) {
      batch.update(roomRef.collection("players").doc(currentHostId), { isHost: false });
    }

    await batch.commit();
    console.log(`[claimHost] roomId=${roomId} newHost=${uid} (${playerData.name})`);
    return { success: true, hostId: uid };
  }
);

// ─── cleanupRoom ─────────────────────────────────────────────────────────────

export const cleanupRoom = onCall(
  { region: "asia-south1", enforceAppCheck: false },
  async (request) => {
    const uid = assertAuth(request.auth);
    const roomId = assertString(request.data?.roomId, "roomId");

    const roomRef = db.collection("rooms").doc(roomId);
    const roomSnap = await roomRef.get();
    if (!roomSnap.exists) return { success: true, deleted: true };

    const playersSnap = await roomRef.collection("players").get();
    const remainingUids = playersSnap.docs.map((d) => d.id);

    // Recursively delete if no players remain, or if only the caller remains and is leaving
    if (remainingUids.length === 0 || (remainingUids.length === 1 && remainingUids[0] === uid)) {
      await db.recursiveDelete(roomRef);
      console.log(`[cleanupRoom] Completely deleted room ${roomId} and all nested subcollections.`);
      return { success: true, deleted: true };
    }

    return { success: false, reason: "Room still has active players." };
  }
);

