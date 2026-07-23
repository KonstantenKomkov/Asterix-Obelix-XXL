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

После начала задачи 83 отчёт различает декларативную достижимость graph и
конкретные renderer/runtime entry points. `concreteRuntimeBindings` учитывает
только bindings, которые точный versioned `runtimeProfiles` selector реально
передаёт исполняемому state machine; `declarativeOnlyBindings` нельзя трактовать
как завершённую runtime-интеграцию. На текущем этапе конкретно интегрированы
полные profiles `asterix-player` и `obelix-player`: 90 selectors Астерикса и
72 selectors Обеликса. Пять стабильных entry states Обеликса и 67 точных
dictionary-slot event entry points охватывают locomotion, idle variants,
attacks/combo, damage/recovery, interactions, traversal, water и swim.
Полный `idefix-player` добавляет ещё 28 selectors: три стабильных состояния и
25 точных dictionary-slot entry points для locomotion, idle variants, attacks,
interactions, death и swim.
Три enemy actor-instance profiles добавляют 85 concrete selectors: 41 для
обычного Roman skin 48, 41 для equipment-слоя лидера skin 27 и три для body
skin 28. Составной лидер требует оба 30-node профиля, а basic Roman — отдельный
28-node профиль; seed entity и номер перехода детерминированно выбирают вариант
для runtime state/event.
Двадцать четыре scripted actor-instance профиля связывают каждый
animated-character/cinematic-scene dictionary owner с отдельными instance,
script event и exact selector. Complete/interrupt возвращают прежнюю позу, а
checkpoint restore сохраняет sequence/state без повторной доставки one-shot;
два cinematic-scene owner не объединяются с scene-data timelines.
Тринадцать world object profiles добавляют 46 exact selectors для machinegun,
mechanism component, activator, checkpoint, двух shop, wild boar, трёх
square-turtle, двух interface и lightning FX. Event lists поддерживают
одновременные tracks, а loop/clamp, commit phase и object/material/particle
synchronization читаются из binding data; restore не повторяет side effects.
Остались только 63 cue-driven selectors cinematic timelines из п. 90.

Проверенный после п. 89 fresh gate содержит 345 bound clips, 408
декларативных bindings и 345 concrete runtime bindings; `unboundClips`,
`unexplainedClips`,
`clipsWithoutRuntimePath` и `unknownBindingClips` равны нулю. SHA-256 отчёта:
`2ec1c2873ba8bddb895548504ba3a550b11ddf804c6de378e1532619a3d6037b`.
Входной подтверждённый каталог сохранил прежний SHA-256
`3f42b0ee77fe59609c93a28adcf42d1f4e17a5f9814b383d0c1528c2afa4fbbc`.

Representative sequences зафиксированы только как versioned metadata в
`assets/animation_visual_acceptance.v1.json`: locomotion/combat Астерикса,
locomotion/combat/swim Обеликса и Идефикса, combat обычного Roman и лидера,
scripted NPC/creature events, machinegun fire/recoil, representative
world/UI/FX events и cinematic scene-data-1. Они сверены side-by-side с локально
установленным оригиналом и разрешаются в точные registry bindings.
Кадры, извлечённые clips и остальные оригинальные/производные игровые ресурсы
остаются вне Git.
