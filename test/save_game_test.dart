import 'dart:convert';

import 'package:asterix_xxl/feature/save/data/save_game_store.dart';
import 'package:asterix_xxl/feature/save/domain/save_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'v2 save survives store recreation with player and world state',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final store = SaveGameStore(preferences);
      final savedAt = DateTime.utc(2026, 7, 21, 18, 30);
      await store.save(
        SaveGame(
          profileId: 'profile-1',
          profileName: 'Asterix',
          checkpointId: 13,
          savedAt: savedAt,
          gameplayState: const {
            'player': {
              'position': <double>[1, 2, 3],
              'health': 2,
            },
            'world': {
              'rewards': 4,
              'levers': <bool>[true],
            },
          },
        ),
      );
      final restored = SaveGameStore(preferences).load();
      expect(restored?.profileId, 'profile-1');
      expect(restored?.checkpointId, 13);
      expect(restored?.savedAt, savedAt);
      expect(
        (restored?.gameplayState['world'] as Map<String, dynamic>)['rewards'],
        4,
      );
    },
  );

  test('v1 save migrates and unsupported schema is rejected', () async {
    final legacy = jsonEncode({
      'schemaVersion': 1,
      'profileId': 'legacy',
      'profileName': 'Gaul',
      'checkpoint': 7,
      'savedAt': '2026-07-21T18:30:00Z',
      'state': {
        'player': {'health': 3},
      },
    });
    final migrated = SaveGame.decode(legacy);
    expect(migrated.profileId, 'legacy');
    expect(migrated.checkpointId, 7);
    expect(
      () => SaveGame.decode('{"schemaVersion":99}'),
      throwsFormatException,
    );
  });

  test('corrupt persisted save fails closed', () async {
    SharedPreferences.setMockInitialValues({SaveGameStore.key: '{broken'});
    final preferences = await SharedPreferences.getInstance();
    expect(SaveGameStore(preferences).load(), isNull);
    expect(
      () => SaveGame.decode(
        '{"schemaVersion":2,"savedAt":7,"profile":{},"checkpointId":0,"gameplayState":{}}',
      ),
      throwsFormatException,
    );
  });
}
