import 'package:flutter/material.dart';

import '../models/game_config.dart';
import '../services/auth_service.dart';
import '../services/game_service_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import 'join_screen.dart';
import 'lobby_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _nameController = TextEditingController();

  bool _isCreating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController.text = AuthService.instance.displayName ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<String?> _promptDisplayName() async {
    final current = AuthService.instance.displayName;

    if (current != null && current.isNotEmpty) {
      return current;
    }

    String? enteredName;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String? localError;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(
                  color: AppColors.cardBorder,
                ),
              ),
              title: const Text(
                'ENTER YOUR NAME',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: AppColors.textPrimary,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Choose a display name so your friends know who you are.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    autofocus: true,
                    maxLength: 20,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter name (2–20 chars)',
                      errorText: localError,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    final valid = AuthService.validateDisplayName(
                      _nameController.text,
                    );

                    if (valid == null) {
                      setDialogState(() {
                        localError = 'Name must be 2–20 characters.';
                      });
                      return;
                    }

                    AuthService.instance.setDisplayName(valid);
                    enteredName = valid;

                    Navigator.of(ctx).pop();
                  },
                  child: const Text('CONTINUE'),
                ),
              ],
            );
          },
        );
      },
    );

    return enteredName;
  }

  void _showCreateGameSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (ctx) {
        final minP = GameConfig.minPlayers;
        final maxP = GameConfig.maxPlayers;

        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 24.0,
            vertical: 28.0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.cardBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'CREATE GAME',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Start a private room and invite your friends.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),

              // Game mode
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.cardBorder,
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.sports_esports_outlined,
                      color: AppColors.primary,
                      size: 24,
                    ),
                    SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Game Mode',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Classic Mafia',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Players
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.cardBorder,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.people_alt_outlined,
                      color: AppColors.secondary,
                      size: 24,
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Players',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$minP–$maxP players',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              PrimaryButton(
                label: 'CREATE ROOM',
                isLoading: _isCreating,
                icon: Icons.add_circle_outline_rounded,
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _handleCreateRoom();
                },
              ),

              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleCreateRoom() async {
    setState(() {
      _errorMessage = null;
    });

    if (!AuthService.instance.isFirebaseAvailable) {
      final reconnected = await AuthService.instance.reconnect();

      if (!reconnected) {
        setState(() {
          _errorMessage = 'Internet connection required to play.';
        });
        return;
      }
    }

    final name = await _promptDisplayName();

    if (name == null) return;

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    try {
      final service = GameServiceProvider.instance.current;

      final room = await service.createRoom(
        hostName: name,
      );

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LobbyScreen(
            roomId: room.id,
            roomCode: room.code,
            isHost: true,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = e.toString().replaceFirst(
              'Exception: ',
              '',
            );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  void _handleJoinRoom() async {
    if (!AuthService.instance.isFirebaseAvailable) {
      final reconnected = await AuthService.instance.reconnect();

      if (!reconnected) {
        setState(() {
          _errorMessage = 'Internet connection required to play.';
        });
        return;
      }
    }

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const JoinScreen(),
      ),
    );
  }

  void _showHowToPlay() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 20.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.cardBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'HOW TO PLAY',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildHowToPlaySection(
                    icon: Icons.shield_outlined,
                    title: 'THE OBJECTIVE',
                    color: AppColors.primary,
                    content:
                        'The town is split into Civilians and secret Mafia.\nCivilians win by identifying and eliminating all Mafia members.\nMafia wins when their numbers equal or exceed living Civilians.',
                  ),
                  const SizedBox(height: 12),
                  _buildHowToPlaySection(
                    icon: Icons.loop_rounded,
                    title: 'THE GAME CYCLE',
                    color: AppColors.secondary,
                    content:
                        '1. NIGHT ACTIONS: Mafia attacks, Doctor protects, Detective investigates, Bodyguard guards.\n2. ROUND RESULT: Public secret eliminations are revealed.\n3. DISCUSSION: Town deliberates for 60 seconds.\n4. VOTING: Town votes on who to eliminate.',
                  ),
                  const SizedBox(height: 12),
                  _buildHowToPlaySection(
                    icon: Icons.groups_outlined,
                    title: 'ROLES',
                    color: AppColors.warning,
                    content:
                        '• MAFIA: Eliminate civilians secretly.\n• DETECTIVE: Investigate one player\'s true identity per round.\n• DOCTOR: Protect one player from death each round.\n• BODYGUARD: Sacrifices self to intercept attacks on their target.\n• VIGILANTE: Single-use lethal shot during secret actions.\n• CIVILIAN: Deduces truth through discussion and voting.',
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: 'GOT IT',
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHowToPlaySection({
    required IconData icon,
    required String title,
    required Color color,
    required String content,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: color,
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = AuthService.instance.isFirebaseAvailable;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 24.0,
            vertical: 20.0,
          ),
          child: Column(
            children: [
              if (!isOnline) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(
                      alpha: 0.15,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primary.withValues(
                        alpha: 0.4,
                      ),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 16,
                        color: AppColors.primaryLight,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Internet connection required to play.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(flex: 2),

              // ============================================================
              // MAFIA LOGO
              // ============================================================
              Flexible(
                child: Image.asset(
                  'assets/images/mafia_logo.png',
                  width: 300,
                  height: 300,
                  fit: BoxFit.contain,
                ),
              ),

              const SizedBox(height: 12),

              // Short supporting tagline.
              const Text(
                'Your friends are lying.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w400,
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(
                      alpha: 0.15,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.danger.withValues(
                        alpha: 0.4,
                      ),
                    ),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],

              const Spacer(flex: 3),

              // ============================================================
              // PRIMARY ACTIONS
              // ============================================================
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PrimaryButton(
                    key: const Key('create_room_button'),
                    label: 'CREATE GAME',
                    isLoading: _isCreating,
                    icon: Icons.add_circle_outline_rounded,
                    onPressed: _showCreateGameSheet,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Start a private game',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SecondaryButton(
                    key: const Key('join_room_button'),
                    label: 'JOIN GAME',
                    icon: Icons.login_rounded,
                    onPressed: _handleJoinRoom,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Enter a room code',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: TextButton.icon(
                      onPressed: _showHowToPlay,
                      icon: const Icon(
                        Icons.help_outline_rounded,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      label: const Text(
                        'HOW TO PLAY',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
