# Сквозная приёмка привязок анимаций LVL01

Приёмка задачи 69 объединяет четыре независимо проверяемых слоя: локальный
семантический asset catalog, 52 animation dictionaries и их 518 slots,
versioned binding registry, а также достижимые hero/character/world/cinematic
runtime graphs. Неизменный `NNNN.animation.json` служит точным join key между
каталогом и registry; более общие semantic action из dictionary-аннотаций не
подменяются предположительными строковыми alias.

Команда создаёт детальный локальный JSON-отчёт:

```sh
make animation-bindings-accept \
  CATALOG="$HOME/asterix-reference/animation-catalog-cinematics-task62.6.json" \
  OUTPUT="$HOME/asterix-reference/animation-binding-acceptance-task69.json"
```

Gate сначала повторяет строгую catalog-приёмку 345 clips / 52 dictionaries /
518 slots. Затем для каждого clip перечисляет объективные dictionary
memberships, все конкретные actor/action/context bindings и хотя бы один путь
выбора из runtime: hero entry graph, character state/event graph, world event
profile или cinematic script event/cue. Неизвестная ссылка registry, clip без
binding, semantic context без clip join или binding без runtime path отклоняют
отчёт.

Проверенный 22 июля 2026 локальный результат содержит 345 bound clips и 408
конкретных bindings; `unboundClips`, `unexplainedClips`,
`clipsWithoutRuntimePath` и `unknownBindingClips` равны нулю. SHA-256 отчёта:
`788767f3cdab72bbdd673df41b64b0204a12663e272a406e8d3b2e7cac42bbcd`.
Входной подтверждённый каталог сохранил прежний SHA-256
`3f42b0ee77fe59609c93a28adcf42d1f4e17a5f9814b383d0c1528c2afa4fbbc`.

Representative sequences зафиксированы только как versioned metadata в
`assets/animation_visual_acceptance.v1.json`: locomotion/combat Астерикса,
machinegun fire/recoil и cinematic scene-data-1. Они сверены side-by-side с
локально установленным оригиналом и разрешаются в точные registry bindings.
Кадры, извлечённые clips и остальные оригинальные/производные игровые ресурсы
остаются вне Git.
