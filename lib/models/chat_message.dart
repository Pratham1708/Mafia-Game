import 'package:cloud_firestore/cloud_firestore.dart';

/// Real-time text message sent during the discussion phase or in spectator chat.
///
/// Firestore paths:
///   Living discussion: rooms/{roomId}/messages/{messageId}
///   Spectator chat:    rooms/{roomId}/spectatorMessages/{messageId}
class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String message;
  final DateTime timestamp;
  final bool isSpectator;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.timestamp,
    this.isSpectator = false,
  });

  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? senderName,
    String? message,
    DateTime? timestamp,
    bool? isSpectator,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      isSpectator: isSpectator ?? this.isSpectator,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'messageId': id,
      'senderId': senderId,
      'senderName': senderName,
      'message': message,
      'timestamp': Timestamp.fromDate(timestamp),
      'isSpectator': isSpectator,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> data, String id) {
    DateTime parsedTimestamp = DateTime.now();
    final rawTs = data['timestamp'];
    if (rawTs is Timestamp) {
      parsedTimestamp = rawTs.toDate();
    } else if (rawTs is String) {
      parsedTimestamp = DateTime.tryParse(rawTs) ?? DateTime.now();
    }

    return ChatMessage(
      id: (data['messageId'] as String?) ?? id,
      senderId: (data['senderId'] as String?) ?? '',
      senderName: (data['senderName'] as String?) ?? 'Player',
      message: (data['message'] as String?) ?? '',
      timestamp: parsedTimestamp,
      isSpectator: (data['isSpectator'] as bool?) ?? false,
    );
  }
}
