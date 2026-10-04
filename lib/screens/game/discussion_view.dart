import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/chat_message.dart';
import '../../models/game_phase.dart';
import '../../models/player.dart';
import '../../models/room.dart';
import '../../services/game_service_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/chat_message_bubble.dart';
import '../../widgets/game_timer_widget.dart';
import '../../widgets/primary_button.dart';

class DiscussionView extends StatefulWidget {
  final String roomId;
  final Room room;
  final Player currentPlayer;
  final List<Player> players;
  final bool isHost;

  const DiscussionView({
    super.key,
    required this.roomId,
    required this.room,
    required this.currentPlayer,
    required this.players,
    required this.isHost,
  });

  @override
  State<DiscussionView> createState() => _DiscussionViewState();
}

class _DiscussionViewState extends State<DiscussionView> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late Stream<List<ChatMessage>> _messagesStream;
  int _lastMessageCount = 0;
  bool _isSending = false;
  bool _isAdvancing = false;
  String? _errorMessage;

  static const List<String> _quickReactions = ['🤔', '👀', '😂', '❗', '🫢'];

  @override
  void initState() {
    super.initState();
    _messagesStream = GameServiceProvider.instance.current.streamMessages(widget.roomId);
    _textController.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(DiscussionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roomId != widget.roomId) {
      _messagesStream = GameServiceProvider.instance.current.streamMessages(widget.roomId);
    }
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSendMessage([String? customText]) async {
    if (!widget.currentPlayer.isAlive) return;

    final text = customText ?? _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    if (text.length > 500) {
      setState(() => _errorMessage = 'Message cannot exceed 500 characters.');
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      final service = GameServiceProvider.instance.current;
      await service.sendMessage(roomId: widget.roomId, message: text);
      if (customText == null) {
        _textController.clear();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _handleAdvanceToVoting() async {
    if (_isAdvancing) return;

    final service = GameServiceProvider.instance.current;
    final currentRoom = await service.streamRoom(widget.roomId).first;
    if (currentRoom.currentPhase != GamePhase.discussion) {
      debugPrint('Discussion auto-advance skipped: room already in ${currentRoom.currentPhase.name}');
      return;
    }

    setState(() => _isAdvancing = true);
    try {
      await service.advanceToVoting(widget.roomId);
    } catch (e) {
      debugPrint('Error advancing to voting: $e');
    } finally {
      if (mounted) setState(() => _isAdvancing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = GameServiceProvider.instance.current;
    final livingCount = widget.players.where((p) => p.isAlive).length;
    final isAlive = widget.currentPlayer.isAlive;

    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Column(
        children: [
          // Sleek Info Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: const Border(
                bottom: BorderSide(color: AppColors.cardBorder, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ROUND ${widget.room.currentRound} • DISCUSSION',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '($livingCount alive)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),

                // Countdown Timer (server-synchronized)
                GameTimerWidget(
                  endTimestampMillis: widget.room.discussionEndTimestamp?.millisecondsSinceEpoch,
                  onTimerExpired: _handleAdvanceToVoting,
                ),
              ],
            ),
          ),

          // Dead player spectator alert banner
          if (!isAlive) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                border: const Border(
                  bottom: BorderSide(color: AppColors.cardBorder, width: 1),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('👻', style: TextStyle(fontSize: 16)),
                  SizedBox(width: 8),
                  Text(
                    'YOU ARE ELIMINATED • You can watch the discussion.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_errorMessage != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.danger.withValues(alpha: 0.15),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          // Discussion Message Feed
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      'Unable to load discussion messages.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  );
                }

                final messages = snapshot.data ?? [];
                if (messages.length > _lastMessageCount) {
                  _lastMessageCount = messages.length;
                  _scrollToBottom();
                }

                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.forum_outlined,
                            size: 40,
                            color: AppColors.textMuted.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'The town floor is open.\nShare suspicions, defend yourself, and prepare for voting.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.senderId == widget.currentPlayer.uid;
                    return ChatMessageBubble(
                      message: msg,
                      isMe: isMe,
                      isSpectatorChannel: false,
                    );
                  },
                );
              },
            ),
          ),

          // Host action bar / waiting banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(
                top: BorderSide(color: AppColors.cardBorder, width: 1),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isHost) ...[
                  PrimaryButton(
                    key: const Key('proceed_to_voting_button'),
                    label: 'PROCEED TO VOTING',
                    icon: Icons.how_to_vote_rounded,
                    isLoading: _isAdvancing,
                    onPressed: _handleAdvanceToVoting,
                  ),
                  const SizedBox(height: 6),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Discussion active — Voting will begin automatically',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      TextButton(
                        key: const Key('claim_host_discussion'),
                        onPressed: () async {
                          try {
                            await service.claimHost(widget.roomId);
                          } catch (_) {}
                        },
                        child: const Text(
                          'Claim Host',
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ],

                // Living players input bar
                if (isAlive) ...[
                  // Quick Reactions
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _quickReactions.map((emoji) {
                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _handleSendMessage(emoji),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                            child: Text(emoji, style: const TextStyle(fontSize: 18)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('chat_input_field'),
                          controller: _textController,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _handleSendMessage(),
                          maxLength: 500,
                          buildCounter: (context,
                                  {required currentLength,
                                  required isFocused,
                                  maxLength}) =>
                              currentLength > 400
                                  ? Text(
                                      '$currentLength/$maxLength',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textMuted,
                                      ),
                                    )
                                  : null,
                          decoration: const InputDecoration(
                            hintText: 'Share your thoughts...',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        key: const Key('chat_send_button'),
                        icon: _isSending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 18),
                        style: IconButton.styleFrom(
                          backgroundColor: _textController.text.trim().isEmpty ||
                                  _isSending
                              ? AppColors.cardBorder
                              : AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(12),
                        ),
                        onPressed:
                            _textController.text.trim().isEmpty || _isSending
                                ? null
                                : () => _handleSendMessage(),
                      ),
                    ],
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    alignment: Alignment.center,
                    child: const Text(
                      'Eliminated players cannot speak in town discussion.',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
