import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Server-timestamp derived countdown timer widget.
///
/// Computes remaining time based on [endTimestampMillis].
/// Does NOT rely on client state as authority; merely renders the remaining
/// duration visually in MM:SS format.
class GameTimerWidget extends StatefulWidget {
  final int? endTimestampMillis;
  final VoidCallback? onTimerExpired;
  final TextStyle? textStyle;
  final bool showBadge;

  const GameTimerWidget({
    super.key,
    required this.endTimestampMillis,
    this.onTimerExpired,
    this.textStyle,
    this.showBadge = true,
  });

  @override
  State<GameTimerWidget> createState() => _GameTimerWidgetState();
}

class _GameTimerWidgetState extends State<GameTimerWidget> {
  Timer? _localTicker;
  int _secondsRemaining = 0;
  bool _expiredReported = false;

  @override
  void initState() {
    super.initState();
    _recalculate();
    _startTicker();
  }

  @override
  void didUpdateWidget(covariant GameTimerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endTimestampMillis != widget.endTimestampMillis) {
      _expiredReported = false;
      _recalculate();
    }
  }

  @override
  void dispose() {
    _localTicker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _localTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _recalculate();
      }
    });
  }

  void _recalculate() {
    if (widget.endTimestampMillis == null || widget.endTimestampMillis! <= 0) {
      if (mounted && _secondsRemaining != 0) {
        setState(() => _secondsRemaining = 0);
      }
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final remainingMillis = widget.endTimestampMillis! - now;
    final seconds = (remainingMillis / 1000).ceil();

    final clamped = seconds > 0 ? seconds : 0;
    if (clamped != _secondsRemaining) {
      if (mounted) {
        setState(() {
          _secondsRemaining = clamped;
        });
      }
    }

    if (clamped == 0 && !_expiredReported) {
      _expiredReported = true;
      widget.onTimerExpired?.call();
    }
  }

  String _formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isUrgent = _secondsRemaining <= 10 && _secondsRemaining > 0;
    final isExpired = _secondsRemaining == 0 && widget.endTimestampMillis != null;

    final Color badgeColor;
    if (isExpired) {
      badgeColor = AppColors.primary;
    } else if (isUrgent) {
      badgeColor = AppColors.warning;
    } else {
      badgeColor = AppColors.accent;
    }

    final timeString = _formatTime(_secondsRemaining);

    final textWidget = Text(
      timeString,
      key: const Key('game_timer_text'),
      style: widget.textStyle ??
          TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: badgeColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
    );

    if (!widget.showBadge) {
      return textWidget;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: badgeColor.withValues(alpha: isUrgent ? 0.8 : 0.4),
          width: isUrgent ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUrgent ? Icons.timer_outlined : Icons.schedule_rounded,
            size: 14,
            color: badgeColor,
          ),
          const SizedBox(width: 6),
          textWidget,
        ],
      ),
    );
  }
}
