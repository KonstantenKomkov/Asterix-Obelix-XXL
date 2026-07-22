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

Точная skin geometry может хранить weights и inverse bind matrices без
собственной копии HAnim hierarchy. Reviewer в таком случае требует отдельный
`hierarchy-skin-object-id` и проверяет его число костей против объявленного
`skin.boneCount`; одного совпадения clip node count для выбора геометрии или
иерархии недостаточно. Для Идефикса exact geometry 0 использует явно связанный
31-bone hierarchy object 1.
