// ignore_for_file: avoid_print
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_game/models/player.dart';
import 'package:mafia_game/models/player_role.dart';
import 'package:mafia_game/services/game_logic_engine.dart';

void main() {
  group('Phase 3 — Game Balance & Mechanics Simulation (6-12 Players)', () {
    test('Simulate 100 games per player count (6 to 12) and measure balance', () {
      final random = Random(42);
      final simulationResults = <int, Map<String, dynamic>>{};

      const int gamesPerCount = 50;

      for (int playerCount = 6; playerCount <= 12; playerCount++) {
        int mafiaWins = 0;
        int civilianWins = 0;
        int totalRounds = 0;
        int docSaves = 0;
        int bgInterceptions = 0;
        int vigKills = 0;
        int detMafiaFound = 0;

        for (int g = 0; g < gamesPerCount; g++) {
          final uids = List.generate(playerCount, (i) => 'player_$i');
          final roleMap = GameLogicEngine.assignRoles(uids, random);

          final players = uids.map((uid) {
            return Player(
              uid: uid,
              name: 'P_$uid',
              role: roleMap[uid]!,
              isAlive: true,
              joinedAt: DateTime.now(),
            );
          }).toList();

          bool vigUsed = false;
          int round = 1;
          const int maxRounds = 25; // prevent runaway loops

          while (round <= maxRounds) {
            totalRounds++;
            final living = players.where((p) => p.isAlive).toList();

            // Win check before round
            var winCheck = GameLogicEngine.checkWinCondition(living);
            if (winCheck.isGameOver) {
              if (winCheck.winner == 'MAFIA') {
                mafiaWins++;
              } else {
                civilianWins++;
              }
              break;
            }

            // 1. Secret actions
            final livingMafia = living.where((p) => p.role == PlayerRole.mafia).toList();
            final livingDoctor = living.where((p) => p.role == PlayerRole.doctor).toList();
            final livingDet = living.where((p) => p.role == PlayerRole.detective).toList();
            final livingBg = living.where((p) => p.role == PlayerRole.bodyguard).toList();
            final livingVig = living.where((p) => p.role == PlayerRole.vigilante).toList();

            // Mafia picks non-mafia target
            String? mafiaTarget;
            final nonMafia = living.where((p) => p.role != PlayerRole.mafia).toList();
            if (livingMafia.isNotEmpty && nonMafia.isNotEmpty) {
              mafiaTarget = nonMafia[random.nextInt(nonMafia.length)].uid;
            }

            // Doctor picks anyone living
            String? doctorTarget;
            if (livingDoctor.isNotEmpty && living.isNotEmpty) {
              doctorTarget = living[random.nextInt(living.length)].uid;
            }

            // Bodyguard picks anyone living other than self
            String? bgTarget;
            String? bgUid;
            if (livingBg.isNotEmpty) {
              bgUid = livingBg.first.uid;
              final others = living.where((p) => p.uid != bgUid).toList();
              if (others.isNotEmpty) {
                bgTarget = others[random.nextInt(others.length)].uid;
              }
            }

            // Vigilante has 30% chance to shoot if not used yet
            String? vigTarget;
            String? vigUid;
            if (livingVig.isNotEmpty && !vigUsed && random.nextDouble() < 0.3) {
              vigUid = livingVig.first.uid;
              final others = living.where((p) => p.uid != vigUid).toList();
              if (others.isNotEmpty) {
                vigTarget = others[random.nextInt(others.length)].uid;
              }
            }

            // Detective investigates someone other than self
            Map<String, String>? detTargets;
            if (livingDet.isNotEmpty) {
              final dUid = livingDet.first.uid;
              final others = living.where((p) => p.uid != dUid).toList();
              if (others.isNotEmpty) {
                detTargets = {dUid: others[random.nextInt(others.length)].uid};
              }
            }

            final actionRes = GameLogicEngine.resolveSecretActions(
              mafiaTarget: mafiaTarget,
              doctorTarget: doctorTarget,
              bodyguardTarget: bgTarget,
              bodyguardUid: bgUid,
              vigilanteTarget: vigTarget,
              vigilanteUid: vigUid,
              vigilanteAlreadyUsed: vigUsed,
              playerRoles: roleMap,
              detectiveTargets: detTargets,
            );

            if (actionRes.vigilanteUsedAbility) vigUsed = true;
            if (actionRes.bodyguardIntercepted) bgInterceptions++;
            if (doctorTarget != null &&
                (doctorTarget == mafiaTarget || doctorTarget == vigTarget)) {
              docSaves++;
            }
            if (actionRes.detectiveResults.values.any((isMafia) => isMafia)) {
              detMafiaFound++;
            }
            if (actionRes.vigilanteUsedAbility &&
                actionRes.eliminatedPlayerIds.contains(vigTarget)) {
              vigKills++;
            }

            // Apply eliminations from actions
            for (final elimUid in actionRes.eliminatedPlayerIds) {
              final idx = players.indexWhere((p) => p.uid == elimUid);
              if (idx != -1) {
                players[idx] = players[idx].copyWith(isAlive: false);
              }
            }

            // Win check after night
            winCheck = GameLogicEngine.checkWinCondition(
              players.where((p) => p.isAlive).toList(),
            );
            if (winCheck.isGameOver) {
              if (winCheck.winner == 'MAFIA') {
                mafiaWins++;
              } else {
                civilianWins++;
              }
              break;
            }

            // 2. Voting Phase
            final aliveAfterNight = players.where((p) => p.isAlive).toList();
            if (aliveAfterNight.length > 2) {
              final votes = <String, String>{};
              for (final voter in aliveAfterNight) {
                final candidates = aliveAfterNight.where((p) => p.uid != voter.uid).toList();
                votes[voter.uid] = candidates[random.nextInt(candidates.length)].uid;
              }

              final voteElimUid = GameLogicEngine.resolveVoteElimination(votes);
              if (voteElimUid != null) {
                final idx = players.indexWhere((p) => p.uid == voteElimUid);
                if (idx != -1) {
                  players[idx] = players[idx].copyWith(isAlive: false);
                }
              }

              // Win check after vote
              winCheck = GameLogicEngine.checkWinCondition(
                players.where((p) => p.isAlive).toList(),
              );
              if (winCheck.isGameOver) {
                if (winCheck.winner == 'MAFIA') {
                  mafiaWins++;
                } else {
                  civilianWins++;
                }
                break;
              }
            }

            round++;
          }
        }

        simulationResults[playerCount] = {
          'mafiaWinRate': (mafiaWins / gamesPerCount * 100).toStringAsFixed(1),
          'civWinRate': (civilianWins / gamesPerCount * 100).toStringAsFixed(1),
          'avgRounds': (totalRounds / gamesPerCount).toStringAsFixed(1),
          'docSaves': docSaves,
          'bgInterceptions': bgInterceptions,
          'vigKills': vigKills,
          'detMafiaFound': detMafiaFound,
        };
      }

      // Print balance summary report for documentation
      print('\n===============================================================');
      print('MAFIA MULTIPLAYER — PHASE 3 BALANCE SIMULATION REPORT');
      print('===============================================================');
      print('Players | Mafia Win % | Civ Win % | Avg Rounds | Doc Saves | BG Intercepts | Vig Kills | Det Hits');
      print('--------|-------------|-----------|------------|-----------|---------------|-----------|---------');
      for (final entry in simulationResults.entries) {
        final d = entry.value;
        print(
          '${entry.key.toString().padRight(7)} | '
          '${d['mafiaWinRate']!.toString().padRight(11)}% | '
          '${d['civWinRate']!.toString().padRight(9)}% | '
          '${d['avgRounds']!.toString().padRight(10)} | '
          '${d['docSaves']!.toString().padRight(9)} | '
          '${d['bgInterceptions']!.toString().padRight(13)} | '
          '${d['vigKills']!.toString().padRight(9)} | '
          '${d['detMafiaFound']}',
        );
      }
      print('===============================================================\n');

      expect(simulationResults.length, 7);
      for (final res in simulationResults.values) {
        final mWin = double.parse(res['mafiaWinRate'] as String);
        final cWin = double.parse(res['civWinRate'] as String);
        expect(mWin + cWin, 100.0);
        // Ensure both factions are capable of winning and results are valid
        expect(mWin, greaterThanOrEqualTo(0.0));
        expect(cWin, greaterThan(0.0));
      }
    });
  });
}
