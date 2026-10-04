import 'dart:math';

/// Generates unambiguous, human-readable 6-character room codes.
/// Excludes confusing characters: '0', 'O', '1', 'I'.
class RoomCodeGenerator {
  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static final Random _random = Random.secure();

  /// Generates a 6-character room code like "K7XM2P".
  static String generate([int length = 6]) {
    final buffer = StringBuffer();
    for (int i = 0; i < length; i++) {
      buffer.write(_alphabet[_random.nextInt(_alphabet.length)]);
    }
    return buffer.toString();
  }

  /// Sanitizes and validates room code format.
  static String sanitize(String input) {
    return input.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  /// Checks if format is 6 characters alphanumeric.
  static bool isValid(String code) {
    final sanitized = sanitize(code);
    return sanitized.length == 6 && RegExp(r'^[A-Z0-9]{6}$').hasMatch(sanitized);
  }
}
