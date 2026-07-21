import 'dart:convert';

final class SaveGame {
  const SaveGame({
    required this.profileId,
    required this.profileName,
    required this.checkpointId,
    required this.savedAt,
    required this.gameplayState,
  });

  static const schemaVersion = 2;
  final String profileId;
  final String profileName;
  final int checkpointId;
  final DateTime savedAt;
  final Map<String, Object?> gameplayState;

  String encode() => jsonEncode({
    'schemaVersion': schemaVersion,
    'profile': {'id': profileId, 'name': profileName},
    'checkpointId': checkpointId,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'gameplayState': gameplayState,
  });

  factory SaveGame.decode(String encoded) {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Save root must be an object.');
    }
    final migrated = _migrate(decoded);
    final profile = migrated['profile'];
    final state = migrated['gameplayState'];
    final checkpoint = migrated['checkpointId'];
    final savedAtValue = migrated['savedAt'];
    final savedAt = savedAtValue is String
        ? DateTime.tryParse(savedAtValue)
        : null;
    if (profile is! Map<String, dynamic> ||
        profile['id'] is! String ||
        (profile['id'] as String).isEmpty ||
        profile['name'] is! String ||
        checkpoint is! int ||
        checkpoint < 0 ||
        savedAt == null ||
        state is! Map<String, dynamic>) {
      throw const FormatException('Save payload is invalid.');
    }
    return SaveGame(
      profileId: profile['id'] as String,
      profileName: profile['name'] as String,
      checkpointId: checkpoint,
      savedAt: savedAt.toUtc(),
      gameplayState: Map<String, Object?>.from(state),
    );
  }

  static Map<String, dynamic> _migrate(Map<String, dynamic> source) {
    final version = source['schemaVersion'];
    if (version == 2) return source;
    if (version == 1) {
      return {
        'schemaVersion': 2,
        'profile': {
          'id': source['profileId'] ?? 'default',
          'name': source['profileName'] ?? 'Игрок',
        },
        'checkpointId': source['checkpoint'] ?? 0,
        'savedAt': source['savedAt'],
        'gameplayState': source['state'],
      };
    }
    throw FormatException('Unsupported save schema: $version.');
  }
}
