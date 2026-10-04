/// Central configuration parameters for Mafia Multiplayer.
/// Centrally configurable so they can be changed without modifying multiple files.
class GameConfig {
  /// Production default is false (real authenticated players only).
  /// Can be set to true during automated test runs or debug/testing suites.
  static bool testingMode = false;

  /// Duration of the discussion phase in seconds.
  static const int defaultDiscussionDurationSeconds = 60;

  /// Duration of the voting phase in seconds before timeout auto-resolve.
  static const int defaultVotingDurationSeconds = 45;

  /// Duration of secret actions phase in seconds before timeout auto-resolve.
  static const int defaultActionsDurationSeconds = 45;

  /// Maximum length for discussion chat messages.
  static const int maxChatMessageLength = 500;

  /// Minimum number of players required to start a game.
  /// Production games support 4–12 real players (minimum = 4).
  static const int minPlayers = 4;

  /// Maximum capacity of a game room.
  static const int maxPlayers = 12;
}
