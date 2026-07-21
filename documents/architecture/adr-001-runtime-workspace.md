# ADR-001: границы runtime workspace

- Статус: принято
- Дата: 21 июля 2026
- Контекст: M2, задачи 17–22

## Решение

Приложение остаётся одним Flutter macOS product, но runtime разделяется на
слои с односторонними зависимостями:

```text
Flutter UI / Dart application
       │ commands + snapshots через versioned C ABI
       ▼
engine/include ── engine/src (simulation, scene, resources, audio)
                         │ immutable render snapshot
                         ▼
                    engine/metal
                         ▲
macos/Runner ── MTKView, display/lifecycle/input bridge

bin + lib/importer ── offline package ──► engine/src loader
```

### Владение ответственностью

| Область | Владелец | Не делает |
|---|---|---|
| Меню, настройки, HUD, навигация экранов, accessibility | Flutter widgets / Dart | не рендерит 3D и не владеет игровыми объектами |
| UI state и orchestration сессии | Dart application layer | не шагает simulation по объектам через FFI |
| Парсинг оригинальных KWN/RWS и сборка package | `bin/`, `lib/importer/` | не входит в shipped frame loop, не читает файлы игры во время gameplay |
| ABI, opaque handles, POD messages | `engine/include` | не экспортирует C++ STL/Objective-C типы |
| Scene, fixed-step simulation, gameplay, collision, animation, runtime resources/audio | `engine/src` C++ | не вызывает Flutter и AppKit |
| GPU resources, pipelines, command buffers, frame encoding | `engine/metal` Objective-C++/Metal | не принимает gameplay decisions |
| `MTKView`, Retina drawable size, app/window lifecycle, device input bridge | `engine/macos` + `macos/Runner` Swift/Objective-C++ | не хранит authoritative simulation state |

`engine/src` — platform-neutral C++20. Metal и AppKit types не проходят через
его публичные headers. Importer остаётся Dart-инструментом до появления
измеренной причины переносить parser в native code.

## Данные и владение памятью

- Dart владеет UI state и пакетами команд до успешной передачи через ABI.
- `EngineHandle` — opaque pointer; C++ создаёт и уничтожает всё состояние
  сессии. Ровно один owner закрывает handle через `asterix_engine_destroy`.
- Runtime loader владеет CPU-копиями package resources. Renderer владеет Metal
  objects и освобождает их только после завершения использующих command buffers.
- Simulation публикует immutable render snapshots в double buffer. Update пишет
  back snapshot, renderer читает front snapshot; swap выполняется атомарно на
  границе fixed tick. Указатели внутрь snapshot не выдаются Dart.
- ABI использует вызывающим выделенные buffers либо функции `size/copy`; память,
  выделенная в одном runtime/allocator, не освобождается другим.
- Stable object IDs приходят из versioned package manifest. Адреса, индексы
  vector и Metal handles никогда не являются persistent IDs.

## Потоки исполнения

1. Main thread принадлежит AppKit/Flutter и обслуживает UI и lifecycle.
2. Display callback `MTKView` кодирует Metal frame на renderer thread/queue и
   читает только опубликованный render snapshot.
3. Simulation выполняется на выделенном serial engine thread с fixed timestep.
   Она пакетно забирает input/commands из bounded SPSC queue.
4. Resource IO/decompression может работать в worker pool; публикация ресурса в
   scene происходит на simulation boundary, GPU upload — через renderer queue.
5. Dart получает не callbacks на каждый объект, а ограниченную event queue и
   компактный UI snapshot не чаще одного раза на Flutter frame.

ABI-вызовы, помеченные main-thread-only, проверяют поток в debug. Методы enqueue
не блокируют main thread; при заполнении bounded queue возвращается явный status.

## C ABI

Публичный header начинается с ABI version и C linkage. Минимальные семейства:

```c
uint32_t asterix_engine_abi_version(void);
AsterixStatus asterix_engine_create(const AsterixEngineConfig*, EngineHandle**);
void asterix_engine_destroy(EngineHandle*);
AsterixStatus asterix_engine_enqueue(EngineHandle*, const AsterixCommandBatch*);
AsterixStatus asterix_engine_copy_ui_snapshot(EngineHandle*, AsterixUiSnapshot*);
AsterixStatus asterix_engine_drain_events(EngineHandle*, AsterixEvent*, size_t*);
```

Каждая ABI struct содержит `struct_size` и `abi_version`; новые поля добавляются
только в конец. Enum имеет фиксированный `uint32_t` transport. Strings — UTF-8
pointer + byte length на время вызова. Исключения не пересекают ABI: все ошибки
становятся `AsterixStatus`, расширенная диагностика копируется отдельной функцией.
Несовместимая major ABI version завершает создание до выделения GPU ресурсов.

Platform channel допустим только для редких AppKit operations (file picker,
window/fullscreen), но не для engine commands или frame state. Основной transport
после задачи 21 — Dart FFI поверх C ABI.

## Lifecycle

Состояния native session:

```text
absent → created → surfaceAttached ⇄ suspended
                    │       │
                    └───────┴──→ surfaceDetached → destroyed
```

1. Flutter открывает game screen; bridge создаёт engine и MTKView, затем
   attach surface. Повторный attach без detach возвращает ошибку.
2. Resize передаёт drawable pixels и scale после изменения backing scale;
   нулевой drawable допустим при сворачивании и не создаёт frame.
3. Background/sleep останавливает display callbacks и simulation accumulation,
   дожидается in-flight GPU work, но сохраняет session resources.
4. Foreground возобновляет clock с новым origin, не проигрывая накопленное
   wall-clock время как simulation ticks.
5. Уход с game screen сначала останавливает новые commands/display callbacks,
   затем detach surface, flush GPU, join engine workers и destroy handle.
6. Все stop/detach/destroy операции идемпотентны. Ошибка частичного create идёт
   по тому же обратному пути освобождения.

Flutter hot restart рассматривается как потеря Dart owner: macOS bridge обязан
закрыть прежнюю сессию перед регистрацией новой.

## Структура workspace

```text
lib/                     Flutter UI/application и FFI wrapper
bin/, lib/importer/      offline importer
engine/include/          installed C ABI headers
engine/src/              platform-neutral C++ runtime
engine/metal/            .metal и Objective-C++ renderer
engine/macos/            MTKView/AppKit bridge
engine/tests/            native unit/integration tests
macos/Runner/            тонкая Swift composition layer
test/                    Dart/importer/widget tests
```

Xcode Runner линкует один static native target. Native tests запускаются без
Flutter. Generated FFI bindings не редактируются вручную и проверяются на
совпадение ABI в CI.

## Последствия и проверки

Такое разделение оставляет Flutter отзывчивым, не создаёт мелких FFI-вызовов на
каждый объект и позволяет тестировать simulation без Metal. Цена — явная
синхронизация snapshots, versioned ABI и два набора build tooling.

Задачи 18–22 обязаны проверить это решение: universal build и native tests,
MTKView resize/Retina, повторный lifecycle, ABI integration test, bounded queues
и стабильный 60 FPS test scene. Любое отступление оформляется новым ADR, а не
неявной зависимостью между слоями.
