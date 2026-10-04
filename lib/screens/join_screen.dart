import 'package:flutter/material.dart';
import '../models/room.dart';
import '../services/auth_service.dart';
import '../services/game_service_provider.dart';
import '../theme/app_theme.dart';
import '../utils/room_code_generator.dart';
import '../widgets/primary_button.dart';
import 'game/game_screen.dart';
import 'lobby_screen.dart';

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController.text = AuthService.instance.displayName ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleJoin() async {
    final nameValid = AuthService.validateDisplayName(_nameController.text);
    if (nameValid == null) {
      setState(() {
        _errorMessage = 'Name must be between 2 and 20 characters.';
      });
      return;
    }
    AuthService.instance.setDisplayName(nameValid);

    final rawCode = _codeController.text.trim();
    if (rawCode.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a 6-character room code.';
      });
      return;
    }

    final sanitizedCode = RoomCodeGenerator.sanitize(rawCode);
    if (!RoomCodeGenerator.isValid(sanitizedCode)) {
      setState(() {
        _errorMessage = 'Room code must be exactly 6 letters/numbers (e.g. K7XM2P).';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final service = GameServiceProvider.instance.current;
      final room = await service.joinRoom(
        roomCode: sanitizedCode,
        playerName: nameValid,
      );

      if (!mounted) return;
      if (room.status == RoomStatus.playing) {
        // Reconnecting player directly into the active match!
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => GameScreen(
              roomId: room.id,
              roomCode: room.code,
            ),
          ),
        );
      } else {
        final currentUid = AuthService.instance.currentUid;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => LobbyScreen(
              roomId: room.id,
              roomCode: room.code,
              isHost: room.hostId == currentUid,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      String friendlyError = msg;
      if (msg.contains('Room not found')) {
        friendlyError = 'Room not found. Check the 6-character code and try again.';
      } else if (msg.contains('full')) {
        friendlyError = 'This room is already full (12 players maximum).';
      } else if (msg.contains('already started') || msg.contains('in progress')) {
        friendlyError = 'This game is already in progress.';
      }
      setState(() {
        _errorMessage = friendlyError;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'JOIN GAME',
          style: TextStyle(letterSpacing: 2.0, fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              const Text(
                'YOUR NAME',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                maxLength: 20,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Enter your name',
                  counterText: '',
                  prefixIcon: Icon(Icons.person_outline_rounded, color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'ENTER ROOM CODE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 28,
                    letterSpacing: 8.0,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w900,
                  ),
                  decoration: InputDecoration(
                    hintText: 'K7XM2P',
                    hintStyle: TextStyle(
                      color: AppColors.textMuted.withValues(alpha: 0.5),
                      letterSpacing: 8.0,
                    ),
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(vertical: 18),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 16, right: 8),
                      child: Icon(Icons.tag_rounded, color: AppColors.secondary),
                    ),
                  ),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: AppColors.danger, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 36),

              PrimaryButton(
                label: 'JOIN GAME',
                isLoading: _isLoading,
                icon: Icons.login_rounded,
                onPressed: _handleJoin,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
