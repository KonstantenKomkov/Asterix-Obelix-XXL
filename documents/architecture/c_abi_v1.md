# C ABI v1 и Dart transport

## Назначение

ABI v1 — единственная runtime-граница между Dart orchestration и C++ core.
Публичный контракт находится в `engine/include/asterix/engine.h`, а Dart
bindings генерируются из него командой `make ffi-generate`. C++ STL,
Objective-C и Metal-типы границу не пересекают.

## Версионирование и память

- `ASTERIX_ENGINE_ABI_VERSION` равен `1`; несовместимая версия отклоняется до
  создания worker thread.
- Каждая составная входная/выходная структура начинается с `struct_size` и
  `abi_version`. Поля можно добавлять только в конец.
- `AsterixEngineHandle` opaque. Его создаёт C++ и ровно один Dart owner закрывает
  через `asterix_engine_destroy`; `NativeFinalizer` остаётся страховкой утечки.
- Массивы команд и событий выделяет вызывающая сторона. Native runtime не
  возвращает указателей на внутренние snapshots и не требует освобождать свою
  память из Dart.
- Исключения не пересекают ABI и преобразуются в `AsterixStatus`.

## Пакетный обмен

`asterix_engine_enqueue` принимает `AsterixCommandBatch`, поэтому один FFI-вызов
переносит все команды Flutter frame. Текущие команды v1 — установка pause и
прибавление тестового score. Неизвестный command type отклоняет весь batch.

Команды помещаются атомарно в bounded SPSC ring максимальной ёмкости 256.
Переполнение возвращает `ASTERIX_STATUS_QUEUE_FULL`; частичная запись batch не
допускается. Единственный simulation worker читает команды последовательно и
не вызывает Dart callbacks.

После каждой применённой команды worker копирует опубликованный front snapshot
в back buffer, обновляет состояние и атомарно меняет front index. Копирование в
Dart защищено короткой секцией только на границе swap; указатель на buffer не
выдаётся. UI читает один компактный `AsterixUiSnapshot` не чаще Flutter frame.

События складываются в отдельный bounded SPSC ring и выгружаются пачкой через
`asterix_engine_drain_events`. Очередь lossy при переполнении, но каждую потерю
фиксирует `dropped_event_count` в snapshot: UI может обнаружить разрыв и
перечитать authoritative состояние, а не полагаться на событие как на
единственное хранилище.

## Сборка и проверка

Runner принудительно включает объект C API из static library и экспортирует
символы для `DynamicLibrary.process()`. Для integration-теста
`scripts/build_native_ffi_test.sh` собирает dylib из того же `engine.cpp`, после
чего Dart вызывает реальные ABI symbols и проверяет batch → worker → snapshot →
events. `make check` воспроизводит эту сборку до запуска Flutter tests.
