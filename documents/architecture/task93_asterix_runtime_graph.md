# Runtime-граф анимаций Астерикса

## Граница gameplay и animation

`player_runtime.hpp` хранит только gameplay-факты: состояние движения/боя,
capsule, скорость, здоровье и направление. Прямые animation timers, выбор
одного из восьми клипов и locomotion blend из него удалены.

`player_animation_runtime.hpp` преобразует подтверждённые gameplay-факты в
authored selector ID и передаёт их единому `AnimationController`. Публичный
`select(binding)` делает все 90 bindings достижимыми только как
`select:<binding>`; выбрать clip, dictionary или slot в обход graph нельзя.
Контроллер остаётся единственным владельцем binding, transition, cursor,
phase, completion и activation.

Physics-состояние `fall`, возникающее при вершине траектории, не считается
authored guard и не заменяет активный `jump`/`double_jump`. Поэтому обычный
прыжок сохраняет dictionary 0 / slot 13 / `clip-0031`, а второй прыжок явно
переключает controller на dictionary 0 / slot 35 / `clip-0064`. Приземление,
урон и другие доказанные interrupts могут завершить воздушный клип.

## ASTPAK и Metal

Slice proof и pipeline переносят канонический
`asterix.authored-graph.v1.json` в ASTPAK как resource
`authored-animation-graph`. Metal строго требует profile
`actor:CKHkAsterix`, 90 states и 90 transitions, связывает каждый graph state
с соответствующим 58-joint clip и создаёт native controller.

Fixed simulation tick сначала обновляет gameplay, затем controller. Renderer
не читает gameplay enum или `state_seconds` для выбора pose: он получает
готовый controller snapshot, находит clip по его authored binding и sampling
выполняет по `cursor_seconds`. Диагностический ручной preview остаётся
отдельным явно включаемым путём и не участвует в gameplay runtime.

## Проверки

Native regressions доказывают доступность всех 90 selectors через controller,
slot 13 / `clip-0031` до и после apex и отдельный slot 35 / `clip-0064` для
double jump. Pipeline tests проверяют детерминированную упаковку graph
resource. Полный authored pose blending, root-motion policies и render
interpolation остаются предметом п. 93.5.
