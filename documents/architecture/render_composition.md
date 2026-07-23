# Data-driven render composition

ASTPAK больше не трактует один `skin objectId` как полную модель. Pipeline
строит ресурс `render-composition` schema v1 из подтверждённых animation
bindings и явных многослойных связей
`assets/render_composition_overrides.v1.json`.

Каждая composition имеет identity `actor/costume/context`, общую bone palette и
упорядоченные обязательные слои с собственной ролью и skin payload. Для
`LVL01` подтверждены составные chains:

- `asterix/default/gameplay`: body 4 + winged helmet 3, 58 bones;
- `obelix/default/gameplay`: body 2 + costume overlay 1, 58 bones;
- `basic-enemy-leader:roman/roman-default/gameplay`: body 28 + equipment
  overlay 27, 31 bones.

Остальные экспортированные skins получают однозначную однослойную composition
из actor bindings. Несколько разных skins с одинаковой identity без override,
необъяснённый skin, отсутствующий обязательный слой, повторяющаяся роль или
разное число bones завершают сборку структурированной ошибкой.

Metal runtime разрешает Asterix composition по
`asterix/default/gameplay`, загружает body и accessory из manifest и передаёт
обоим одну 58-joint palette. Отсутствующий, malformed или неоднозначный manifest
больше не приводит к marker/partial-model fallback.

## Post-build acceptance

23 июля 2026 свежий локальный пакет из исходного `LVL01` содержал 38 skins и
42 compositions без `unexplainedSkinObjectIds`. `audit-slice-assets` принял
Asterix, Obelix, basic-enemy leader, animated-character NPC и mechanism
component representatives. Fresh и cached packages совпали побайтно:

`bf8c3b4dddea50101ce913bd50d3539179d5da5dc48c52e355daf7615ea72b1b`.

Debug cold-start на свежем пакете подтвердил отрисовку body и крылатой шапки
Asterix с общей animated palette; локальный Retina PNG и ASTPAK оставлены вне
Git. Другие representative actors пока не создаются gameplay vertical slice,
поэтому их acceptance выполняется на package composition/material payload до
подключения actor spawning в content cycle.
