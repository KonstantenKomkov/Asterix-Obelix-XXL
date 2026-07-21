import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'generated/engine_bindings.dart';

class EngineCommand {
  const EngineCommand(this.type, this.value);

  const EngineCommand.setPaused(bool paused)
    : this(ASTERIX_COMMAND_SET_PAUSED, paused ? 1 : 0);

  const EngineCommand.addScore(int amount)
    : this(ASTERIX_COMMAND_ADD_SCORE, amount);

  final int type;
  final int value;
}

class EngineSnapshot {
  const EngineSnapshot({
    required this.generation,
    required this.score,
    required this.paused,
    required this.pendingCommands,
    required this.droppedEventCount,
  });

  final int generation;
  final int score;
  final bool paused;
  final int pendingCommands;
  final int droppedEventCount;
}

class EngineEvent {
  const EngineEvent({
    required this.type,
    required this.commandType,
    required this.value,
    required this.generation,
  });

  final int type;
  final int commandType;
  final int value;
  final int generation;
}

class EngineFfiException implements Exception {
  const EngineFfiException(this.operation, this.status);

  final String operation;
  final int status;

  @override
  String toString() => 'EngineFfiException($operation, status: $status)';
}

class EngineFfi implements Finalizable {
  EngineFfi._(
    this._bindings,
    this._handle,
    this._finalizerToken,
    this._finalizer,
  );

  factory EngineFfi.open(
    DynamicLibrary library, {
    int commandCapacity = 64,
    int eventCapacity = 64,
  }) {
    final bindings = AsterixEngineBindings(library);
    if (bindings.asterix_engine_abi_version() != ASTERIX_ENGINE_ABI_VERSION) {
      throw const EngineFfiException(
        'abi_version',
        ASTERIX_STATUS_INCOMPATIBLE_ABI,
      );
    }

    final config = calloc<AsterixEngineConfig>();
    final outHandle = calloc<Pointer<AsterixEngineHandle>>();
    try {
      config.ref
        ..struct_size = sizeOf<AsterixEngineConfig>()
        ..abi_version = ASTERIX_ENGINE_ABI_VERSION
        ..command_capacity = commandCapacity
        ..event_capacity = eventCapacity;
      final status = bindings.asterix_engine_create(config, outHandle);
      _check('create', status);
      final finalizer = NativeFinalizer(
        library
            .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
              'asterix_engine_destroy',
            )
            .cast(),
      );
      final engine = EngineFfi._(
        bindings,
        outHandle.value,
        Object(),
        finalizer,
      );
      engine._finalizer.attach(
        engine,
        outHandle.value.cast(),
        detach: engine._finalizerToken,
      );
      return engine;
    } finally {
      calloc.free(config);
      calloc.free(outHandle);
    }
  }

  factory EngineFfi.openPath(
    String path, {
    int commandCapacity = 64,
    int eventCapacity = 64,
  }) => EngineFfi.open(
    DynamicLibrary.open(path),
    commandCapacity: commandCapacity,
    eventCapacity: eventCapacity,
  );

  factory EngineFfi.process({
    int commandCapacity = 64,
    int eventCapacity = 64,
  }) => EngineFfi.open(
    DynamicLibrary.process(),
    commandCapacity: commandCapacity,
    eventCapacity: eventCapacity,
  );

  final AsterixEngineBindings _bindings;
  Pointer<AsterixEngineHandle> _handle;
  final Object _finalizerToken;
  final NativeFinalizer _finalizer;

  bool get isClosed => _handle == nullptr;

  void enqueue(List<EngineCommand> commands) {
    _ensureOpen();
    final nativeCommands = calloc<AsterixCommand>(commands.length);
    final batch = calloc<AsterixCommandBatch>();
    try {
      for (var index = 0; index < commands.length; ++index) {
        nativeCommands[index]
          ..type = commands[index].type
          ..reserved = 0
          ..value = commands[index].value;
      }
      batch.ref
        ..struct_size = sizeOf<AsterixCommandBatch>()
        ..abi_version = ASTERIX_ENGINE_ABI_VERSION
        ..commands = nativeCommands
        ..command_count = commands.length;
      _check('enqueue', _bindings.asterix_engine_enqueue(_handle, batch));
    } finally {
      calloc.free(batch);
      calloc.free(nativeCommands);
    }
  }

  EngineSnapshot snapshot() {
    _ensureOpen();
    final native = calloc<AsterixUiSnapshot>();
    try {
      native.ref
        ..struct_size = sizeOf<AsterixUiSnapshot>()
        ..abi_version = ASTERIX_ENGINE_ABI_VERSION;
      _check(
        'copy_ui_snapshot',
        _bindings.asterix_engine_copy_ui_snapshot(_handle, native),
      );
      return EngineSnapshot(
        generation: native.ref.generation,
        score: native.ref.score,
        paused: native.ref.paused != 0,
        pendingCommands: native.ref.pending_commands,
        droppedEventCount: native.ref.dropped_event_count,
      );
    } finally {
      calloc.free(native);
    }
  }

  List<EngineEvent> drainEvents({int capacity = 64}) {
    _ensureOpen();
    final nativeEvents = calloc<AsterixEvent>(capacity);
    final count = calloc<Size>()..value = capacity;
    try {
      _check(
        'drain_events',
        _bindings.asterix_engine_drain_events(_handle, nativeEvents, count),
      );
      return List.generate(count.value, (index) {
        final event = nativeEvents[index];
        return EngineEvent(
          type: event.type,
          commandType: event.command_type,
          value: event.value,
          generation: event.generation,
        );
      });
    } finally {
      calloc.free(count);
      calloc.free(nativeEvents);
    }
  }

  void close() {
    if (isClosed) {
      return;
    }
    _finalizer.detach(_finalizerToken);
    _bindings.asterix_engine_destroy(_handle);
    _handle = nullptr;
  }

  void _ensureOpen() {
    if (isClosed) {
      throw const EngineFfiException('closed', ASTERIX_STATUS_STOPPED);
    }
  }

  static void _check(String operation, int status) {
    if (status != ASTERIX_STATUS_OK) {
      throw EngineFfiException(operation, status);
    }
  }
}
