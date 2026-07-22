# Скелет и анимация XXL1 PC

## Источники

Общие анимации и `CKSkinGeometry` находятся в `LVLnn.KWN`. У оригинальной PC-версии таблица классов level header защищена, но её открытая копия присутствует в локальном `GameModule.elb`. Импортёр находит header по сигнатуре, читает payload из исходного `LVL` и не изменяет ни один исходный файл.

```sh
fvm dart run bin/importer.dart extract-animations \
  /path/to/LVL001/LVL01.KWN /path/to/GameModule.elb \
  "$HOME/asterix-reference/animations/LVL01"
```

Результат — JSON с ключевыми кадрами, тремя контрольными samples каждого clip,
полной render geometry, HAnim hierarchy, vertex bone indices/weights и inverse
bind matrices. До задачи 28 skin JSON ошибочно не сохранял render geometry;
старые proof/ASTPAK необходимо пересобрать. Производные данные сохраняются вне Git.

## Animation manager

`CAnimationManager` (`category=13`, `classId=8`) содержит `RwAnimAnimation` chunks (`0x1B`): version, scheme, flags, duration и keyframes. Поддержаны схемы 1 (float quaternion/translation, frame size 36) и 2 (16-bit compressed values, frame size 24). Число узлов определяется начальной последовательностью кадров с `time=0`; byte offset предыдущего кадра переводится в index через frame size.

Конвертер линейно интерполирует translation и quaternion с нормализацией, затем строит local 4×4 matrix. В `LVL01` подтверждены 345 clips; каждый успешно sampled в `t=0`, `duration/2` и `duration`.

## Animation dictionaries и семантический аудит

`CAnimationDictionary` (`category=9`, `classId=1`) содержит число слотов и
индекс `CAnimationManager` для каждого слота. Значение `0xFFFFFFFF` означает
пустой слот. Инвентаризация словарей воспроизводится без записи исходных данных
в репозиторий:

```sh
fvm dart run bin/importer.dart inventory-animations \
  /path/to/LVL001/LVL01.KWN /path/to/GameModule.elb \
  "$HOME/asterix-reference/animation-inventory.json"
```

Для проверенного PC `LVL01` команда находит 52 словаря и 518 слотов. Объединение
непустых слотов содержит ровно все 345 индексов manager, неизвестных и
непривязанных индексов нет. Это доказывает структурную полноту, но не семантику:
формат словаря не хранит названия действий, loop policy, переходы, root motion
или events. Эти поля должны подтверждаться ссылкой на владельца словаря,
наблюдением воспроизведения и анализом transforms; номер слота или clip сам по
себе методом подтверждения не считается.

Serialized object references дополнительно связывают все 52 словаря с их
владельцами. Источник ссылки подтверждается layout соответствующего класса в
XXL-Editor: например, dictionary 2 — `CKHkAsterix.heroAnimDict`, dictionary 1 —
`CKHkObelix.heroAnimDict`, dictionary 0 — `CKHkIdefix.heroAnimDict`; также
покрыты enemy/NPC hooks, механизмы, cinematic scene data и animation-driven FX.
Для 49 словарей поле типизировано как `CAnimationDictionary`; ссылки трёх
оставшихся словарей из generic `CKObject`-полей явно помечены `generic-field`.
Сырые совпадения 32-битных значений сохраняются отдельно от подтверждённых
`dictionaryOwnerReferences`, чтобы обычное числовое поле не было принято за
object reference.

Объективные метрики и все вхождения clip в словари сводятся в черновик:

```sh
fvm dart run bin/animation_catalog.dart build-draft \
  "$HOME/asterix-reference/animation-inventory.json" \
  "$HOME/asterix-reference/animations/LVL01" \
  "$HOME/asterix-reference/animation-catalog-draft.json"
```

Для XXL1 HAnim node 0 является неподвижным scene root, а authored root motion
находится в translation node 1. Поэтому `analysis.motionRootNodeIndex` равен 1
для многокостных clips (0 для единственного node), и
`rootTranslationDelta`/`rootMotionDistance` вычисляются именно по нему. Reviewer
может получать точный `skin-object-id`: подбор иерархии только по числу bones
небезопасен, поскольку разные персонажи используют одинаковое их количество.
При наличии geometry точный skin также добавляет три контрольных skinned-mesh
силуэта к фронтальной и боковой skeleton-проекциям. Для дополнительной проверки
на свежем локальном ASTPAK profile runtime принимает строго opt-in переменную
`ASTERIX_ANIMATION_REVIEW_CLIP=NNNN`; без неё gameplay bindings не меняются.

Черновик намеренно помечает каждый clip как `unreviewed`. Финальный валидатор
принимает только `confirmed` и требует owner, skin, costume, действие/событие,
`loop`/`one-shot`, root motion, явные списки вариантов, переходов и events, а
также хотя бы одну ссылку на метод подтверждения. Поэтому автоматически
вычисленные близость первой/последней позы и root translation не превращаются
без проверки в недостоверную семантическую классификацию:

```sh
make animation-catalog-validate INPUT=/path/to/catalog.json
```

Результаты ручного просмотра хранятся отдельно от воспроизводимого черновика и
накладываются командой:

```sh
fvm dart run bin/animation_catalog.dart apply-annotations \
  /path/to/draft.json /path/to/annotations.json /path/to/catalog.json
```

Команда разрешает менять только семантические поля и отклоняет неизвестные или
повторяющиеся clip ID, а также попытки подменить объективные метрики. Статус
`provisional` предназначен для обоснованных, но ещё не полностью проверенных
гипотез; финальную валидацию он не проходит. HTML reviewer поддерживает фильтры
по словарю, числу костей и списку clip ID, чтобы сравнивать одинаковые слоты
словарей владельцев без автоматического объявления их семантики.

Финальный `confirmed` дополнительно требует массив `contexts`, который покрывает
каждое вхождение clip в dictionary ровно один раз. Context повторяет owner,
skin/costume, action, playback, transitions, root motion, events и evidence для
конкретных `dictionaryId`/`slot`. Это не позволяет общему gameplay/cinematic
track считаться полностью разобранным после подтверждения только одного вызова.

## Skeleton и skin

Иерархия читается из HAnim extension `0x11E` frame list: node ID/index, hierarchy flags и keyframe size. Skin extension `0x116` содержит bone count, used-bone map, четыре bone indices и четыре weights на vertex, затем inverse bind matrices.

В `LVL01` найдено 39 `CKSkinGeometry`; 38 полностью конечных portable skins экспортируются. Один legacy object содержит non-finite float и не записывается как JSON: его object ID явно перечислен в `excludedNonFiniteSkinObjectIds`, чтобы повреждение не маскировалось. Для multi-costume объектов текущий proof экспортирует первый costume; полный выбор costumes остаётся задачей asset pipeline.

Структура сопоставлена с `RwAnimAnimation`, `RwExtHAnim`, `RwExtSkin`, `CAnimationManager` и `CKSkinGeometry` в [XXL-Editor revision d606cfc](https://github.com/AdrienTD/XXL-Editor/tree/d606cfccf8faa31287aa1326fa9d10c292c06157).

Промежуточная приёмка каталога конкретного владельца не требует преждевременно
подтверждать остальные 51 словарь. При этом для выбранных clips по-прежнему
обязательны contexts всех их вхождений, в том числе cinematic:

```sh
fvm dart run bin/animation_catalog.dart validate-dictionary 2 \
  "$HOME/asterix-reference/animation-catalog-task62.json"
```

Для совместной приёмки нескольких владельцев можно передать их словари одним
scoped-запуском. Это сохраняет требование всех shared contexts для затронутых
clips, но не требует преждевременно подтверждать словари остальных персонажей:

```sh
fvm dart run bin/animation_catalog.dart validate-dictionaries 0,1 \
  "$HOME/asterix-reference/animation-catalog-task62.json"
```

Character-scope LVL01 задаётся версионированным набором из 25 словарей:
gameplay dictionaries basic enemy/leader и dictionaries всех
`CKHkAnimatedCharacter`. В него намеренно не входят boar, turtle, mechanisms,
UI и FX — они относятся к world-scope п. 62.5. Воспроизводимая сборка и
проверка annotations выполняются так:

```sh
make animation-character-annotations \
  INPUT="$HOME/asterix-reference/animation-catalog-heroes-task62.3.json" \
  OUTPUT="$HOME/asterix-reference/animation-semantics-characters-task62.4.json"
fvm dart run bin/animation_catalog.dart apply-annotations \
  "$HOME/asterix-reference/animation-catalog-heroes-task62.3.json" \
  "$HOME/asterix-reference/animation-semantics-characters-task62.4.json" \
  "$HOME/asterix-reference/animation-catalog-characters-task62.4.json"
make animation-characters-validate \
  INPUT="$HOME/asterix-reference/animation-catalog-characters-task62.4.json"
```

Идентификатор skin в character annotations является устойчивым semantic
profile конкретного dictionary и HAnim node count. Он не утверждает связь с
geometry только по совпадению числа костей. Enemy slots группируются в
spawn/awareness, locomotion, combat, damage, death и special families; каждый
slot остаётся отдельным context/variant. Для одноразовых animated-character
dictionaries действие фиксируется как scripted performance, а конкретный
cinematic timeline будет уточнён в п. 62.6. Импортированные clips не содержат
отдельного event track, поэтому `events` остаётся пустым, а не заполняется
предположительными hit windows.

Точная skin geometry может хранить weights и inverse bind matrices без
собственной копии HAnim hierarchy. Reviewer в таком случае требует отдельный
`hierarchy-skin-object-id` и проверяет его число костей против объявленного
`skin.boneCount`; одного совпадения clip node count для выбора геометрии или
иерархии недостаточно. Для Идефикса exact geometry 0 использует явно связанный
31-bone hierarchy object 1.

World-scope LVL01 включает 13 dictionaries: machinegun `19`, shops `20–21`,
activator `22`, mechanism component `23`, square turtles `24–26`, checkpoint
`29`, wild boar `30`, lightning FX `49` и interface `50–51`. В них находятся
46 заполненных slots и 45 уникальных clips. Character dictionaries `27–28` и
cinematic dictionaries исключены из этого scope намеренно. Воспроизводимая
сборка и scoped-приёмка выполняются так:

```sh
make animation-world-annotations \
  INPUT="$HOME/asterix-reference/animation-catalog-characters-task62.4.json" \
  OUTPUT="$HOME/asterix-reference/animation-semantics-world-task62.5.json"
fvm dart run bin/animation_catalog.dart apply-annotations \
  "$HOME/asterix-reference/animation-catalog-characters-task62.4.json" \
  "$HOME/asterix-reference/animation-semantics-world-task62.5.json" \
  "$HOME/asterix-reference/animation-catalog-world-task62.5.json"
make animation-world-validate \
  INPUT="$HOME/asterix-reference/animation-catalog-world-task62.5.json"
```

Каждый slot имеет отдельный world action/event context, owner, playback policy,
переходы и root-motion policy. Повтор clip `0321` в двух slots shop dictionary
сохраняется как два context, а не схлопывается. Импортированный
`RwAnimAnimation` содержит только skeletal keyframes и не содержит отдельного
event track; поэтому `events: []` является подтверждённым отсутствием authored
events, а будущие gameplay/VFX cues должны быть добавлены отдельным versioned
track в п. 68.

Cinematic-scope состоит из 14 dedicated dictionaries `3`, `5–16` и `18`,
связанных типизированным полем `CKCinematicSceneData.animDict`. Дополнительная
ссылка scene data 10 на dictionary `0` заимствует gameplay dictionary Идефикса и
не меняет владельца его slots; scene-specific действия Идефикса представлены
отдельными dictionaries `8` и `18`. Dictionaries `7`, `9` и `10` одновременно
используются animated-character hooks, поэтому их contexts сохраняют обе
структурные роли через точного владельца каждого dictionary membership.

Воспроизводимая сборка 63 cinematic slots / 44 уникальных clips выполняется так:

```sh
make animation-cinematic-annotations \
  INPUT="$HOME/asterix-reference/animation-catalog-world-task62.5.json" \
  OUTPUT="$HOME/asterix-reference/animation-semantics-cinematics-task62.6.json"
fvm dart run bin/animation_catalog.dart apply-annotations \
  "$HOME/asterix-reference/animation-catalog-world-task62.5.json" \
  "$HOME/asterix-reference/animation-semantics-cinematics-task62.6.json" \
  "$HOME/asterix-reference/animation-catalog-cinematics-task62.6.json"
make animation-cinematics-validate \
  INPUT="$HOME/asterix-reference/animation-catalog-cinematics-task62.6.json"
```

Каждый cinematic context фиксирует actor/prop profile, scene-data owner,
dictionary slot как timeline membership, действие, playback, transitions и
root-motion policy. Имена конкретных сюжетных сцен не угадываются без
event-to-scene mapping: устойчивое назначение выражено через scene data object
и timeline slot. Shared gameplay clips получают отдельное cinematic действие,
не теряя contexts hero dictionaries, а authored events не выдумываются.

Финальная машинная приёмка LVL01 выполняется отдельным dataset-specific gate:

```sh
make animation-catalog-accept \
  INPUT="$HOME/asterix-reference/animation-catalog-cinematics-task62.6.json"
```

Gate фиксирует объективные totals исходного набора: ровно 345 manager clips,
52 словаря и 518 структурных slots. Каждый заполненный slot обязан иметь ровно
один объективный membership, а каждый membership — ровно один confirmed
semantic context. Полная семантическая проверка дополнительно исключает
`unreviewed`, `provisional`, `excluded`, пустые обязательные поля и clips без
evidence. Пустые slots входят в структурные 518, но не создают вымышленный
context; в LVL01 заполнены 449 slots.
