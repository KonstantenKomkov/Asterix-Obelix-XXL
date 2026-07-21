import 'package:asterix_xxl/native/engine_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Dart exchanges command batches, snapshots and events through C ABI',
    () async {
      final engine = EngineFfi.openPath(
        'build/native_ffi/libasterix_engine.dylib',
      );
      addTearDown(engine.close);

      engine.enqueue(const [
        EngineCommand.addScore(40),
        EngineCommand.addScore(2),
        EngineCommand.setPaused(true),
      ]);

      EngineSnapshot snapshot = engine.snapshot();
      for (
        var attempt = 0;
        attempt < 100 && snapshot.generation < 3;
        ++attempt
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        snapshot = engine.snapshot();
      }

      expect(snapshot.generation, 3);
      expect(snapshot.score, 42);
      expect(snapshot.paused, isTrue);
      expect(snapshot.pendingCommands, 0);
      expect(snapshot.droppedEventCount, 0);

      final events = engine.drainEvents();
      expect(events, hasLength(3));
      expect(events.map((event) => event.generation), [1, 2, 3]);
      expect(events.last.commandType, 1);

      engine.close();
      expect(engine.isClosed, isTrue);
    },
  );

  test('bounded command queue rejects an oversized batch atomically', () {
    final engine = EngineFfi.openPath(
      'build/native_ffi/libasterix_engine.dylib',
      commandCapacity: 2,
    );
    addTearDown(engine.close);

    expect(
      () => engine.enqueue(const [
        EngineCommand.addScore(1),
        EngineCommand.addScore(2),
        EngineCommand.addScore(3),
      ]),
      throwsA(isA<EngineFfiException>()),
    );
    expect(engine.snapshot().generation, 0);
  });

  test('event overflow is bounded and observable in the snapshot', () async {
    final engine = EngineFfi.openPath(
      'build/native_ffi/libasterix_engine.dylib',
      eventCapacity: 1,
    );
    addTearDown(engine.close);
    engine.enqueue(const [
      EngineCommand.addScore(1),
      EngineCommand.addScore(1),
      EngineCommand.addScore(1),
    ]);

    EngineSnapshot snapshot = engine.snapshot();
    for (var attempt = 0; attempt < 100 && snapshot.generation < 3; ++attempt) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      snapshot = engine.snapshot();
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
    snapshot = engine.snapshot();

    expect(engine.drainEvents(), hasLength(1));
    expect(snapshot.droppedEventCount, 2);
  });
}
