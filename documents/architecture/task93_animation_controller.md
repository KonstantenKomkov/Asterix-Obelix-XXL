# Native AnimationController

## Граница ответственности

`animation_controller.hpp` исполняет versioned authored graph п. 93.2 на
фиксированном simulation tick. Gameplay остаётся владельцем фактов и guards:
после их разрешения он передаёт контроллеру authored transition ID
`select:*` и явное решение `interrupt` либо `queue`. Контроллер не включает
`player_runtime.hpp`, не принимает gameplay enum и не выводит имя клипа из
семантического состояния.

Входной `Graph` сохраняет profile, state/transition IDs, точный
dictionary/slot/asset binding, длительность клипа, playback rate, initial
phase, completion и blend. При создании отклоняются неполные, повторные и
неоднозначные state/selector связи.

## Детерминированное состояние

`Snapshot` содержит активные profile/state/transition, binding,
completion policy, clip cursor, normalized phase, completion flag,
монотонный activation serial, исходную сторону blend и queued transition.
`advance(fixed_dt)`:

- оборачивает loop cursor без повторной активации;
- зажимает one-shot на authored clip end;
- удерживает последнюю pose для `landing` до отдельного gameplay fact;
- продвигает blend тем же fixed tick;
- при pause не меняет ни одно поле.

Повторный selector активного state является no-op. Поэтому удерживаемый факт
не сбрасывает cursor и завершённый one-shot не проигрывается повторно.
Queued transition активируется один раз после completion. `restore`
транзакционно валидирует весь snapshot, возвращает сохранённый activation
serial и не испускает новую активацию.

## Проверки

Native unit-тесты покрывают loop, one-shot, authored clip completion,
interrupt, queued transition, внешний landing completion, pause/restore,
blend cursor и отсутствие replay. Полный runtime-граф Астерикса и передача
готового snapshot в Metal относятся к п. 93.4.
