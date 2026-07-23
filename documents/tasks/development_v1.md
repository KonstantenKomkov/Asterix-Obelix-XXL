# Первая итерация разработки — Asterix & Obelix XXL для macOS

Задачи сформированы из [плана переписывания](../flutter_macos_rewrite_plan.md). Выполненные пункты следует переносить в [completed_v1.md](completed_v1.md).

**Статус:** выполняется. Vertical slice M4 принят; следующий этап — решение о продолжении.

**Цель итерации:** пройти путь от прямого импорта исходных игровых файлов и фиксации эталонного поведения до полностью проходимого вертикального среза одного уровня. Видео не используется как источник моделей, сцен, текстур, анимаций или звука.

**Главное ограничение:** оригинальные бинарники и игровые ресурсы не должны попадать в Git. В репозитории хранятся только новый код, документация форматов и минимальные законные тестовые фикстуры.

---

## Бэклог

Порядок номеров отражает исходную декомпозицию, а не обязательный порядок завершения. Есть два независимых потока: импорт исходных файлов (6–16) и верификация поведения оригинала (4–5 и контрольные состояния из 7). Экранная запись допустима только как необязательный измерительный журнал и не является входом asset pipeline. До завершения importer proof (M1) не следует расширять gameplay или переносить полный контент.

Сложность: **S** — небольшая, **M** — средняя, **L** — крупная, **XL** — исследовательская задача без надёжной предварительной оценки.

| № | Задача | Этап / веха | Приоритет | Сложность | Зависимости / критерий готовности |
|---:|---|---|---|---|---|
| 43 | **Сформировать решение о продолжении:** обновить оценку полного переноса по фактической стоимости исследования, импорта, рендера и gameplay | Gate после M4 | P0 | M | После п. 42; зафиксировано решение continue/re-scope/stop |
| 91 | **Восстановить точные соответствия authored animation clips игровым действиям:** исследовать доступный исходный код, символы, таблицы состояний и обращения к animation dictionaries оригинальной игры; заменить предположительные semantic labels доказанными actor/state/event → dictionary/slot/clip связями | Animation fidelity | P0 | XL | Законный локальный источник; документированная цепочка доказательств для каждого runtime binding; отдельно подтверждены одинарный/двойной прыжок Астерикса; обновлены catalog, bindings и acceptance; визуальный preview не считается достаточным доказательством |

Декомпозиция п. 91 зафиксирована в
[плане reverse engineering](../architecture/original_animation_reverse_engineering.md):

| № | Подзадача | Результат / gate |
|---:|---|---|
| 91.8 | Восстановить world/UI/FX и cinematics | Доказаны 13 world profiles и все cues 14 timelines |
| 91.9 | Добавить versioned provenance schema и strict gate | Каждый binding биективно связан с binary/function/state/dictionary/slot/clip evidence |
| 91.10 | Обновить catalog, registry и acceptance | 408 confirmed; 0 unresolved/ambiguous/visual-only; single/double jump приняты отдельно |

---

## Последующие итерации

Эти работы не входят в первую итерацию и детализируются только после успешной приёмки вертикального среза.

| № | Задача | Веха | Зависимости |
|---:|---|---|---|
| 44 | Переносить каждый уровень циклом: импорт и валидация → триггеры/скрипты → уникальные механики → сверка → полное прохождение → save/load → оптимизация | M5 | После п. 43 и положительного решения |
| 45 | Исследовать старый `AOXXL.sav` и принять решение о совместимости | M5 | После стабилизации новой модели сохранений, п. 39 |
| 46 | Добавить unit, golden, visual regression и smoke-тесты загрузки всех уровней | M5–M6 | По мере переноса контента |
| 47 | Провести полную тест-матрицу: Intel/Apple Silicon, версии macOS, Retina, мониторы, sleep/wake, input hot-plug и аварийное восстановление | M6 | После content complete |
| 48 | Профилировать CPU, GPU, память, размер приложения и startup time; закрыть утверждённые бюджеты | M6 | После п. 44–47 |
| 49 | Настроить подпись, Hardened Runtime, notarization и упаковку `.dmg`/`.pkg` | M6 | После п. 1 и готовности release candidate |
| 50 | Проверить установку и прохождение на чистой системе без Flutter SDK, Xcode, Wine и Windows executable | M6 | После п. 49 |

---

## Сжато по волнам

1. **Подготовка и эталон:** п. 1–7 → M0.
2. **Importer proof:** п. 8–16 → M1. Это главный ранний риск проекта.
3. **Metal proof:** п. 17–22 → M2.
4. **Asset pipeline и базовый движок:** п. 23–31 → M3.
5. **Gameplay vertical slice:** п. 32–39.
6. **Аудио, presentation и приёмка:** п. 40–43 → M4.
7. **Полный контент и выпуск:** п. 44–50 → M5–M6, только после отдельного решения.

---

## Нерешённые вопросы

1. Есть ли подтверждённые права на распространение кода, персонажей, музыки, озвучки и оригинальных ресурсов, или продукт должен поставляться только как движок с локальным импортёром?
2. Какой фрагмент уровня выбран для вертикального среза?
3. Какая минимальная версия macOS и какая минимальная модель Intel/Apple Silicon принимаются за performance baseline?
4. Где проходит граница gameplay orchestration между Dart и C++ после измерения стоимости FFI?

---

## Прогресс

- [x] П. 1 — модель разработки и распространения ресурсов
- [x] П. 2 — защита репозитория
- [x] П. 3 — выбран vertical slice: Gaul, Stage 1 + save boundary
- [x] П. 4 — эталонное поведение vertical slice
- [x] П. 5 — эталонные параметры и погрешности
- [x] П. 6 — каталог контента Gaul/LVL001
- [x] П. 7 — карта файлов и контрольные состояния
- [x] П. 8–15 — исследование форматов
- [x] П. 16 — M1: importer proof
- [x] П. 17 — архитектура workspace и runtime
- [x] П. 18 — структура и Xcode targets нативного ядра
- [x] П. 19 — MTKView platform view и Retina-resize
- [x] П. 20 — lifecycle Metal renderer
- [x] П. 21 — versioned C ABI и Dart FFI transport
- [x] П. 22 — M2: Metal scene proof и Flutter HUD
- [x] П. 23 — ASTPAK 1.0, manifest schema и устойчивые object IDs
- [x] П. 24 — воспроизводимый asset pipeline
- [x] П. 25 — валидация, кеш и инкрементальная сборка ресурсов
- [x] П. 26 — импортированная статическая сцена в Metal
- [x] П. 27 — scene graph и streaming секций
- [x] П. 28 — скелетная анимация и материалы
- [x] П. 29 — фиксированный simulation timestep
- [x] П. 30 — коллизии мира и движение капсулы
- [x] П. 31 — debug tooling базового 3D-движка, M3
- [x] П. 32 — клавиатура, контроллеры, remapping и hot-plug
- [x] П. 33 — state machine Астерикса
- [x] П. 34 — gameplay-камера
- [x] П. 35 — боевая система и первая комбинация
- [x] П. 36–39 — игровые системы vertical slice
- [x] П. 40 — аудио vertical slice
- [x] П. 41 — presentation MVP
- [x] П. 42 — приёмка M4
- [ ] П. 43 — решение о продолжении
- [ ] П. 44–50 — полный контент, качество и release candidate
- [x] П. 54 — иконка исходного приложения во Flutter-проекте
- [x] П. 57 — двойной прыжок
- [x] П. 58 — управляемая высота прыжка
- [x] П. 59 — locomotion-анимации при движении
- [x] П. 60 — эталонная скорость движения
- [x] П. 61 — следование gameplay-камеры за игроком
- [x] П. 62.1 — инфраструктура полного семантического каталога
- [x] П. 62.2 — анимации Астерикса
- [x] П. 62.3 — анимации Обеликса и Идефикса
- [x] П. 62.4 — анимации врагов, NPC и персонажей
- [x] П. 62.5 — анимации объектов, механизмов, UI и FX
- [x] П. 62.6 — cinematic dictionaries и shared contexts
- [x] П. 62.7 — финальная приёмка 345 clips / 518 slots
- [x] П. 63 — data-driven реестр привязок анимаций
- [x] П. 64 — полный animation graph управляемых героев
- [x] П. 65 — animation graphs врагов, NPC и персонажей
- [x] П. 66 — анимации объектов, окружения и механизмов
- [x] П. 67 — scripted/cinematic анимации
- [x] П. 68 — animation events и синхронизация gameplay
- [x] П. 69 — сквозная приёмка полноты всех привязок
- [x] П. 70 — collision-safe следование gameplay-камеры
- [x] П. 71 — бег по умолчанию при старте gameplay; ходьба только в scripted/cinematic-сценах
- [x] П. 72 — анимированный огонь на горящих домах
- [x] П. 73 — анимация движения воды
- [x] П. 74 — позиция и каменный ассет передвигаемого блока первого уровня
- [x] П. 75 — устранение провалов капсулы сквозь поверхность карты
- [x] П. 76 — тени и интерьерное затемнение внутри домов
- [x] П. 77 — полный аудит non-skeletal FX первого уровня
- [x] П. 78 — реальная ASTPAK-интеграция воды и повторная post-build приёмка артефактов п. 74
- [x] П. 79 — authored `CFogBoxNodeFx` без static fallback
- [x] П. 80 — аудит составных render-ресурсов и устранение partial-asset fallback
- [x] П. 81 — согласованное направление управления, перемещения и ориентации Астерикса
- [x] П. 83 — сквозной runtime-аудит и правильная привязка всех анимаций игры
- [x] П. 84 — оставшиеся 82 runtime bindings Астерикса
- [x] П. 85 — 72 runtime bindings Обеликса
- [x] П. 86 — 28 runtime bindings Идефикса
- [x] П. 87 — 85 runtime bindings врагов и лидеров
- [x] П. 88 — 24 scripted bindings NPC и существ
- [x] П. 89 — 46 world/UI/FX bindings
- [x] П. 90 — 63 cinematic bindings
- [ ] П. 91 — точные соответствия анимаций по исходному коду и управляющим таблицам оригинальной игры
  - [x] П. 91.1 — binary corpus и воспроизводимый toolchain
  - [x] П. 91.2 — class/function anchors
  - [x] П. 91.3 — animation dictionary access primitives
  - [x] П. 91.4 — numeric state/event dispatch
  - [x] П. 91.5 — полный профиль Астерикса и отдельные single/double jump chains
  - [x] П. 91.6 — профили Обеликса и Идефикса
  - [x] П. 91.7 — enemies и scripted actors
  - [ ] П. 91.8 — world/UI/FX и cinematics
  - [ ] П. 91.9 — versioned provenance gate
  - [ ] П. 91.10 — итоговые catalog, registry и acceptance
- [x] П. 51 — реальные skeletal clips и полная 58-bone palette Астерикса
- [x] П. 52 — fidelity материалов и геометрии Gaul
- [x] П. 53 — visual regression запуска Gaul

---

**Последнее обновление:** 23 июля 2026 — п. 91.7 выполнен: доказаны все 85 bindings basic Roman и составного Roman leader, включая три синхронных body/equipment выбора, а также 24 отдельных scripted dictionary owner. Два независимых metadata-only export побайтно совпали.

**Предыдущее обновление:** 23 июля 2026 — п. 91.6 выполнен: все 72 bindings Обеликса и 28 bindings Идефикса соединены с numeric runtime state/event, dictionary 0, slot и authored clip; пять reused-clip групп сохраняют отдельные runtime bindings. Два независимых metadata-only export побайтно совпали.

**Предыдущее обновление:** 23 июля 2026 — п. 91.5 выполнен: все 90 bindings Астерикса соединены с numeric runtime state, dictionary 0, slot и authored clip; single jump доказан отдельной цепочкой до slot 13 / `clip-0031`, double jump — до slot 35 / `clip-0064`. Два независимых metadata-only export побайтно совпали.

**Предыдущее обновление:** 23 июля 2026 — п. 91.4 выполнен: numeric handlers закреплены для всех 27 animation owners; восстановлены 5 индексированных jump tables, 63 branch entries и 2 lookup-карты. Semantic labels не присваивались. Два независимых metadata-only export побайтно совпали.

**Предыдущее обновление:** 23 июля 2026 — п. 91.3 выполнен: восстановлены start/change, blend, completion и cinematic play/stop primitives, три dictionary slot selector и 49 прямых xrefs; call graph построен от vtable anchors всех 27 owners с явным разделением direct paths и data-owner/indirect dispatch. Два независимых metadata-only export побайтно совпали.

**Предыдущее обновление:** 23 июля 2026 — п. 91.2 выполнен: class-registration records, factories, vptr stores, vtables и доказанные virtual-slot prefixes восстановлены для 27 animation owners всех групп; 40 dictionary/index fields связаны с чистым XXL-Editor revision, unresolved отсутствуют. Два независимых metadata-only export побайтно совпали.

**Предыдущее обновление:** 23 июля 2026 — п. 91.1 выполнен: точная локальная версия зафиксирована как 2 PE32 x86-модуля и 108 KWN с детерминированным manifest; подтверждены sections/imports и отсутствие debug directory, PDB/MAP и стандартных MSVC RTTI descriptors. Два независимых metadata-only запуска дали одинаковый SHA-256; Ghidra 12.1.2 / OpenJDK 21 и clean-project headless export закреплены для последующего анализа.

**Предыдущее обновление:** 23 июля 2026 — п. 91 декомпозирован на 91.1–91.10: от фиксации точной версии stripped PE32 и восстановления RTTI/vtable/function anchors до provenance gate для всех 408 bindings. Декомпиляция и динамические traces выполняются только локально; в Git разрешены хеши, RVA-идентификаторы, восстановленные числовые связи и собственные валидаторы, но не листинги или псевдокод оригинала.

**Предыдущее обновление:** 23 июля 2026 — добавлен исследовательский п. 91: прежние structural/visual gates не доказали семантическую правильность всех привязок. Требуется восстановить точные actor/state/event → dictionary/slot/clip соответствия из доступного исходного кода, символов и управляющих таблиц оригинальной игры; runtime preview оставлен только как отключённый диагностический инструмент и не является источником истины.

**Предыдущее обновление:** 23 июля 2026 — п. 83 выполнен: итоговый strict gate требует 345 clips / 518 slots / ровно 408 concrete runtime bindings / 0 declarative-only и полный набор 22 representative visual sequences всех групп. Повторно собран fresh ASTPAK всех 345 animations, release cold start прошёл без loader/runtime diagnostics.

**Предыдущее обновление:** 23 июля 2026 — п. 90 выполнен: 14 полных cinematic timeline профилей биективно связывают 63 cues с exact dictionary-slot actor/prop selectors. Native lifecycle поддерживает simultaneous tracks, control/presentation cues, complete/skip/interrupt/resume и restore без replay; fresh gate подтвердил 408 concrete и 0 declarative-only bindings, release-приложение прошло cold start со свежим ASTPAK всех 345 animations.

**Предыдущее обновление:** 23 июля 2026 — п. 89 выполнен: 13 полных world object/event профилей биективно связывают 46 bindings механизмов, shop, fauna, checkpoint, UI и lightning FX с exact dictionary-slot selectors. Native lifecycle поддерживает multi-track event, data-driven loop/commit/synchronization и restore без replay, fresh gate подтвердил 345 concrete и 63 declarative-only bindings, release-приложение прошло cold start со свежим ASTPAK всех 345 animations.

**Предыдущее обновление:** 23 июля 2026 — п. 88 выполнен: 24 scripted actor-instance профиля биективно связывают animated-character/cinematic-scene dictionary owners с уникальными script events и exact selectors. Native lifecycle поддерживает complete/interrupt/restore без replay, fresh gate подтвердил 299 concrete и 109 declarative-only bindings, release-приложение прошло cold start со свежим ASTPAK всех 345 animations.

**Предыдущее обновление:** 23 июля 2026 — п. 87 выполнен: три enemy actor-instance профиля биективно связывают 85 gameplay bindings basic Roman и Roman leader с exact dictionary-slot selectors. Fresh gate подтвердил 275 concrete и 133 declarative-only bindings; Metal отклоняет неполные, повторные, fallback и cross-profile skeleton selectors, release-приложение прошло cold start со свежим ASTPAK всех 345 animations.

**Предыдущее обновление:** 23 июля 2026 — п. 86 выполнен: полный `idefix-player` профиль биективно связывает все 28 gameplay bindings с тремя стабильными и 25 exact dictionary-slot state/event selectors. Fresh gate подтвердил 190 concrete и 218 declarative-only bindings при нулевых error-счётчиках; Metal отклоняет неполный, повторный, fallback или несовместимый с skin 0 / 31-node skeleton профиль, release-приложение загрузило свежий ASTPAK всех 345 animations.

**Предыдущее обновление:** 23 июля 2026 — п. 85 выполнен: полный `obelix-player` профиль биективно связывает все 72 gameplay bindings с пятью стабильными и 67 exact dictionary-slot state/event selectors. Fresh gate подтвердил 162 concrete и 246 declarative-only bindings при нулевых error-счётчиках; Metal отклоняет неполный, повторный, fallback или несовместимый профиль и загрузил свежий ASTPAK всех 345 animations.

**Предыдущее обновление:** 23 июля 2026 — п. 84 выполнен: полный `asterix-player` профиль биективно связывает все 90 gameplay bindings с восемью автоматическими и 82 exact dictionary-slot state/event selectors. Fresh gate подтвердил 90 concrete и 318 declarative-only bindings при нулевых error-счётчиках; Metal отклоняет неполный/повторный профиль и загрузил свежий ASTPAK всех 345 animations.

**Предыдущее обновление:** 23 июля 2026 — оставшиеся после первого этапа п. 83 400 declarative-only bindings декомпозированы по исполняемым группам: п. 84 — Астерикс (82), п. 85 — Обеликс (72), п. 86 — Идефикс (28), п. 87 — враги и лидеры (85), п. 88 — scripted NPC/существа (24), п. 89 — world/UI/FX (46), п. 90 — cinematics (63). П. 83 стал зонтичной итоговой приёмкой с целевыми 408 concrete runtime bindings и нулём declarative-only.

**Предыдущее обновление:** 23 июля 2026 — область п. 83 расширена с одного Астерикса до всех анимаций игры: управляемых героев, врагов, боссов, NPC, существ, объектов, механизмов, environment/particle/material/water FX, UI и scripted/cinematic-сцен. Предыдущие проверки формальной полноты каталога и graph не гарантировали правильное визуальное соответствие runtime-состояний authored clips, поэтому задача требует покадрово принять все 345 clips / 518 slots на фактически достижимых runtime paths, fresh ASTPAK и representative cold-start/scenario sequences без semantic-подмен и silent fallback.

**Предыдущее обновление:** 23 июля 2026 — добавлен п. 83 как аудит анимаций управляемого Астерикса после последовательных расхождений в беге и сальто двойного прыжка; область задачи впоследствии расширена до всех анимаций игры.

**Предыдущее обновление:** 23 июля 2026 — п. 81 исправлен после фактической приёмки: логическое forward action теперь один раз преобразуется в Gaul map-space `-Z`, backward — в `+Z`; facing вычисляется как `atan2(dx, -dz)`, поэтому уже правильная ориентация модели и `←/→` сохранены. Независимые fixed-tick assertions больше не могут принять самосогласованную, но перевёрнутую продольную ось.

**Предыдущее обновление:** 23 июля 2026 — п. 80 выполнен: ASTPAK содержит data-driven manifest 42 render compositions для всех 38 экспортированных skins; явно восстановлены Asterix body 4 + helmet 3, Obelix body 2 + overlay 1 и Roman leader body 28 + overlay 27. Pipeline и runtime отклоняют missing, incompatible, duplicate и ambiguous layers без partial fallback; fresh/cached package совпали, post-build audit и cold-start Asterix с крылатой шапкой приняты.

**Предыдущее обновление:** 22 июля 2026 — п. 82 удалён как преждевременный: красный `enemyMarker` object ID `900002` представляет синтетического proof-противника, которого runtime сам размещает относительно текущего spawn вместе с тестовыми trigger/lever/destructible/reward, а не actor реального уровня. Перенос настоящих spawn/actor bindings относится к content cycle п. 44, а полнота составной модели уже контролируется общим аудитом п. 80.

**Предыдущее обновление:** 22 июля 2026 — добавлен п. 81: после компенсационного поворота authored skin на 180° модель смотрит правильно при `↑`, но capsule перемещается назад относительно карты; при `←/→` displacement верен, однако forward модели направлен против движения. Задача требует устранить несовместимые basis между input, world/camera movement, capsule, model и combat вместо подбора ещё одного знака, а также принять все cardinal/diagonal направления по численным fixed-tick и cold-start visual regressions.

**Предыдущее обновление:** 22 июля 2026 — добавлен п. 80: отсутствие шапки Астерикса локализовано в жёстком выборе только body skin `objectId=4`; крылатая шапка хранится отдельным совместимым 58-bone skin atomic `objectId=3`, который ASTPAK сохранял, но runtime молча не включал в draw composition. Задача требует построить data-driven связи всех составных render-слоёв, найти аналогичные пропуски у персонажей и объектов и закрыть их post-build audit, строгими diagnostics и representative visual regressions без partial-asset fallback.

**Предыдущее обновление:** 22 июля 2026 — п. 79 выполнен: полные payload семи `CFogBoxNodeFx` декодируются до object boundary и упаковываются отдельными ASTPAK resources; Metal семплирует authored volume color/density/transition по simulation clock, а regressions покрывают inside/outside/boundary, streaming, pause и restore без static fallback.

**Предыдущее обновление:** 22 июля 2026 — п. 77 выполнен: полный raw-payload audit классифицировал 60 scene nodes всех пяти секций, 12 particle emitters, 3 water UV-scroll draw ranges и 668 static prelit meshes; необъяснённых non-skeletal animation mechanisms нет. Семь `CFogBoxNodeFx` явно отключены вместо static fallback и вынесены в п. 79 с runtime/visual criteria.

**Предыдущее обновление:** 22 июля 2026 — п. 76 выполнен: RenderWare `rpGEOMETRYPRELIT` RGBA перенесён без потерь в ASTPAK/Metal как authored baked lighting для 668 mesh / 132 268 vertices / 668 draw ranges; level-local collision восстановил cold start внутри дома, а post-build audit, идентичные clean/cached packages и visual smoke исключили silent Lambert fallback и двойное глобальное затемнение.

**Предыдущее обновление:** 22 июля 2026 — п. 75 выполнен: capsule ground contact использует footprint на каждом fixed-tick substep, реальный `CKHkAsterixCheckpoint` и его scene transform входят в ASTPAK и заменили синтетический spawn; post-build gate принял collision всех четырёх секторов (212 meshes / 9423 triangles), а clean/cached packages и cold-start runtime smoke подтвердили единый пакет без провалов на seam/slope/step regressions.

**Предыдущее обновление:** 22 июля 2026 — критерии п. 75–76 усилены по результатам п. 78: collision/checkpoint и authored lighting должны быть доказаны по исходным binding chains и payload свежего установленного ASTPAK; обязательны post-build counts/hashes, cold-start runtime/visual acceptance и проверка clean/cached идентичности без эвристического или синтетического fallback.

**Предыдущее обновление:** 22 июля 2026 — п. 78 выполнен: два `CKHkWaterFall` теперь импортируют три реальные level water surfaces с authored UV multipliers вместо ошибочной маркировки sector-берегов; установленный свежий ASTPAK прошёл post-build gate для 3 water draw ranges и обоих каменных push/pull-блоков, а cache-version исключает старые payloads.

**Предыдущее обновление:** 22 июля 2026 — п. 74 выполнен: `CKHkPushPullAsterix`, level nodes, парные stone meshes/materials и `CKFlaggedPath` ranges импортируются в ASTPAK; Metal использует authored transforms и единый fixed-tick offset для render/collision/interaction, а свежий локальный пакет подтвердил оба блока и texture `it_bloc2_01_mt` без металлического fallback.

**Предыдущее обновление:** 22 июля 2026 — добавлен п. 78: пересборка реального Gaul ASTPAK после п. 73 показала ноль `waterAnimation` bindings — sector meshes содержат только дно/берега `tr_sabl_river_*`, тогда как видимая поверхность создаётся level water hook'ом и не импортируется. Исправление должно перенести hook path и на том же свежем пакете повторно принять фактические scene/material/collision/interaction артефакты п. 74, чтобы cache или синтетические тесты не скрыли пропуск.

**Предыдущее обновление:** 22 июля 2026 — п. 73 выполнен: подтверждён исходный material UV transformation path, шесть водных материалов Gaul получили отдельные направления и скорости, Metal вычисляет фазу от simulation time, а pause/restore/streaming и движение против static fallback покрыты pipeline/native regressions.

**Предыдущее обновление:** 22 июля 2026 — п. 71 выполнен: неверная ходьба локализована в player runtime — acceleration-based gait inference оставлял стартовые тики ниже run threshold; gameplay теперь сразу выбирает эталонные 4,32 world unit/s и run gait, а walk требует явного scripted/cinematic mode; старт Gaul, независимый контрольный collision-сценарий, возврат управления и respawn покрыты native regression.

**Предыдущее обновление:** 22 июля 2026 — п. 70 выполнен: камера представлена объёмом не меньше диагонали near plane, а conservative swept-volume проверки защищают sightline и lateral fixed-tick path, включая весь отрезок render interpolation; тонкая стена, угол и плавный возврат после контакта покрыты native regressions.

**Предыдущее обновление:** 22 июля 2026 — добавлен п. 76: интерьерные тени отсутствуют, потому что pipeline отбрасывает RenderWare pre-lit RGBA, а текущий Metal shader ограничен глобальным ambient и направленным Lambert-светом без shadow/lightmap path; задача должна подтвердить точный механизм оригинала и восстановить его без ухудшения наружного освещения.

**Предыдущее обновление:** 22 июля 2026 — аудит локального proof обнаружил 11 scene-node записей `classId=19` (particle path), но текущий импортёр/Metal runtime до п. 72 не имели общего покрытия non-skeletal FX. Добавлен п. 77 для повторной экстракции с полными payload и фиксации всех оставшихся particle, water/UV, texture-sequence, vertex/material/light animation пропусков без silent static fallback.

**Предыдущее обновление:** 22 июля 2026 — добавлен п. 75: проваливание связано с точечным `groundAt` под центром капсулы после горизонтального шага — на стыке или краю collision-треугольников потеря единственной опоры запускает падение сквозь пол; при `y < -20` fall recovery возвращает игрока в синтетический checkpoint стартовой позиции. Задача также требует проверить исходную collision на реальные разрывы и transforms.

**Предыдущее обновление:** 22 июля 2026 — добавлен п. 74: передвигаемый Астериксом блок первого уровня сейчас смещён относительно оригинала и отображается металлическим; требуется восстановить правильные scene object, transform, геометрию и каменный материал вместе с collision/interaction.

**Предыдущее обновление:** 22 июля 2026 — добавлен п. 73: вода в текущей сборке отображается статично; требуется определить используемый оригиналом механизм, перенести его данные и восстановить эталонное движение водных поверхностей.

**Предыдущее обновление:** 22 июля 2026 — добавлен п. 72: в текущей сборке на горящих домах отсутствует видимый анимированный огонь; требуется восстановить исходные FX-ресурсы, объектные привязки, материалы и эталонный цикл воспроизведения.

**Предыдущее обновление:** 22 июля 2026 — добавлен п. 71: при старте текущей сборки персонаж ходит, тогда как в оригинале управляемое движение по умолчанию является бегом, а ходьба используется в cutscene; задача должна локализовать источник режима (level/spawn, locomotion/input, animation graph или cinematic state), подтвердить область влияния и восстановить эталонное поведение.

**Предыдущее обновление:** 22 июля 2026 — добавлен п. 70: текущий collision avoidance трассирует только точечный отрезок target → candidate и не гарантирует зазор для near plane/объёма камеры или безопасность траектории между snapshots, из-за чего при lateral follow, в углах и во время render interpolation камера может уходить в геометрию.

**Предыдущее обновление:** 22 июля 2026 — п. 61 выполнен: fixed-tick камера следует за фактической позицией капсулы, а единый интерполированный snapshot используется Metal view/projection, frustum/culling/LOD и audio listener; dead-zone и collision follow покрыты regressions.

**Предыдущее обновление:** 22 июля 2026 — п. 69 выполнен: сквозной acceptance gate сопоставляет 345 clips, 52 dictionaries / 518 slots, 408 bindings и достижимые hero/character/world/cinematic runtime paths; unbound, unexplained, unreachable и unknown clips отсутствуют, три representative sequences зафиксированы после визуальной сверки с локальным оригиналом.

**Предыдущее обновление:** 22 июля 2026 — п. 68 выполнен: единые versioned event tracks и fixed-tick sampler доставляют footsteps, gameplay windows, impulses/root motion, world/VFX/SFX/camera cues и one-shot completion без потерь и дублей при low FPS, blend, pause/restore и loop boundary.

**Предыдущее обновление:** 22 июля 2026 — п. 67 выполнен: 14 scene-data timelines связывают подтверждённые 44 clips / 63 cinematic contexts с exact script events и actor cues; camera/audio/subtitle/control, interrupt, skip, checkpoint restore и re-entry покрыты сценарными regressions.

**Предыдущее обновление:** 22 июля 2026 — п. 66 выполнен: 13 точных world profiles связывают подтверждённые 45 clips / 46 contexts механизмов, shops, activator, fauna, checkpoint, interface и FX с runtime events; идемпотентная доставка и restore без повторного side effect покрыты regressions.

**Предыдущее обновление:** 22 июля 2026 — п. 65 выполнен: 27 точных character profiles связывают подтверждённые 92 clips / 109 contexts врагов, leaders, NPC и animated characters с runtime states/events; deterministic variants, reachability, terminal death и совпадение attack impact phase покрыты regressions.

**Предыдущее обновление:** 22 июля 2026 — п. 64 выполнен: полный actor-local graph связывает 90 clips Астерикса, 71 Обеликса и 22 Идефикса с подтверждёнными actions, детерминированными variants, явными transitions и нормализованными clip phases; completeness, reachability и representative skeleton sequences покрыты regressions.

**Предыдущее обновление:** 22 июля 2026 — п. 60 выполнен: бег откалиброван в согласованном масштабе 1 H = 1,8 world unit, полный ввод достигает 2,4 H/с и подтверждённого clip 0035, hysteresis gait, cadence и диагональная нормализация покрыты fixed-tick и visual regression-тестами.

**Предыдущее обновление:** 22 июля 2026 — п. 63 выполнен: renderer разрешает текущие состояния Астерикса из versioned animation binding manifest в ASTPAK; pipeline и runtime диагностируют отсутствующие, неоднозначные и skeleton-incompatible bindings, а clip IDs удалены из кода.

**Предыдущее обновление:** 22 июля 2026 — п. 62.7 выполнен: строгий LVL01 gate принял ровно 345 confirmed clips, 52 dictionaries и 518 структурных slots; все 449 заполненных slots имеют по одному объективному membership и confirmed semantic context, неподтверждённых или необъяснённых значений нет.

**Предыдущее обновление:** 22 июля 2026 — п. 62.6 выполнен: подтверждены 14 dedicated cinematic dictionaries, 63 slots и 44 уникальных clips; каждый scene-data timeline membership получил actor/context/action evidence, а shared hero/animated-character clips сохранили отдельные semantic contexts.

**Предыдущее обновление:** 22 июля 2026 — п. 62.5 выполнен: подтверждены 13 world/UI/FX dictionaries, 46 slots и 45 уникальных clips mechanisms, shops, activator, turtles, checkpoint, boars, interface и lightning; отдельный scoped validator принимает полный world-каталог без cinematic dictionaries.

**Предыдущее обновление:** 22 июля 2026 — п. 62.4 выполнен: подтверждены все 25 character dictionaries, 92 уникальных clips и 109 contexts basic enemies, leaders, NPC и animated characters; отдельный scoped validator принимает полный character-каталог без world dictionaries.

**Предыдущее обновление:** 22 июля 2026 — п. 62.3 выполнен: подтверждены 84 slots / 71 уникальный clip Обеликса и 44 slots / 22 уникальных clips Идефикса, а также 17 дополнительных shared/cinematic contexts; совместный scoped validator принимает dictionaries 0 и 1 с точными skins и полным evidence.

**Предыдущее обновление:** 22 июля 2026 — п. 62.2 выполнен: подтверждены все 108 slots / 90 уникальных clips Астерикса и 10 дополнительных cinematic contexts; локальный scoped validator принимает dictionary 2 с полным evidence и не требует преждевременного завершения остальных словарей.

**Предыдущее обновление:** 22 июля 2026 — исследовательский п. 62 разбит на п. 62.1–62.7: инфраструктура каталога завершена отдельно, дальнейшая семантическая проверка разделена между Астериксом, Обеликсом/Идефиксом, персонажами, миром, cinematics и финальной машинной приёмкой всех 345 clips / 518 slots.

**Предыдущее обновление:** 22 июля 2026 — добавлены п. 62–69: полная инвентаризация всех 345 анимаций, data-driven bindings, исчерпывающие graphs игрока/персонажей/мира/scripted-сцен, единые animation events и сквозная приёмка с нулём необъяснённых clips; п. 60 уточнён как исправление ускоренной ходьбы на эталонный бег с согласованными gait, cadence и скоростью.

**Предыдущее обновление:** 22 июля 2026 — п. 59 повторно проверен на реальном вводе: ошибочный turn/lean clip `0054` заменён настоящим беговым циклом `0035`, найденным в hero animation dictionary и подтверждённым последовательными кадрами при зажатом движении; диагностический override удалён.

**Предыдущее обновление:** 22 июля 2026 — п. 59 выполнен: idle/run palette плавно смешиваются, фаза run-клипа следует фактической скорости капсулы, а модель сохраняет направление движения; fixed-tick и visual pose regressions покрывают оба перехода.

**Предыдущее обновление:** 22 июля 2026 — п. 58 выполнен: раннее отпускание плавно сокращает восходящую фазу обоих прыжков, а удержание в течение 0,2 с сохраняет полную высоту; fixed-tick тесты подтверждают детерминированность минимальной и максимальной траекторий.

**Предыдущее обновление:** 22 июля 2026 — п. 57 выполнен: реализован ровно один дополнительный воздушный импульс с восстановлением только после подтверждённого приземления; переход `fall → jump` и запрет третьего прыжка покрыты native regression-тестом.

**Предыдущее обновление:** 22 июля 2026 — п. 54 выполнен: подтверждённая для использования иконка исходного приложения добавлена во все размеры macOS asset catalog и проверена в release `.app`.

**Предыдущее обновление:** 22 июля 2026 — добавлены п. 59–61 по результату проверки движения: locomotion-анимации, калибровка скорости по оригиналу и подключение gameplay-камеры к позиции капсулы.

**Предыдущее обновление:** 22 июля 2026 — п. 56 выполнен: стрелки проходят через Flutter action snapshot и native axis mapping до capsule controller; key-up и lifecycle reset останавливают движение, включая snapshot до создания viewport.

**Предыдущее обновление:** 22 июля 2026 — п. 55 выполнен: стартовое состояние капсулы вычисляется ground probe по геометрии Gaul, сразу содержит опорную поверхность и остаётся grounded после первого simulation tick.

**Предыдущее обновление:** 22 июля 2026 — добавлены п. 55–58: исправление стартовой позиции и клавиатурного движения Астерикса, двойной прыжок и управляемая высота прыжка.

**Предыдущее обновление:** 22 июля 2026 — п. 53 выполнен: локальные Retina-кадры двух холодных запусков Gaul автоматически сверяются по глобальной сцене и зоне персонажа; PNG и ASTPAK остаются вне Git.

**Предыдущее обновление:** 22 июля 2026 — добавлен п. 54: копирование и настройка иконки исходного приложения во Flutter-проекте.

**Предыдущее обновление:** 22 июля 2026 — п. 52 выполнен: material slots разрешаются корректно, Metal учитывает alpha/cutout, addressing и filtering; аудит 663 mesh не нашёл неверных indices или потерянных texture bindings.

**Предыдущее обновление:** 22 июля 2026 — п. 51 выполнен: gameplay states Астерикса используют реальные 58-node clips LVL01, RenderWare tracks/HAnim hierarchy восстанавливаются в runtime, полная palette передаётся в Metal без T-pose fallback.

**Предыдущее обновление:** 21 июля 2026 — п. 42 выполнен: многосекторный ASTPAK содержит STR01_00–03, vertical-slice сценарий принят по movement/combat/death/checkpoint/save/audio, ограничения fidelity переданы в gate п. 43.

**Предыдущее обновление:** 21 июля 2026 — п. 41 выполнен: launch/menu/profile/settings flow адаптирован к 560×420 и 1440×900, fullscreen связан с NSWindow, ru/en locale и управляемые субтитры применяются без перезапуска.

**Предыдущее обновление:** 21 июля 2026 — п. 40 выполнен: AVAudioEngine воспроизводит импортированный WAV как music/ambience beds, spatial effects следуют gameplay events и camera listener, channel priorities и независимые уровни громкости покрыты тестами.

**Предыдущее обновление:** 21 июля 2026 — п. 35 выполнен: data-driven combat runtime реализует hitbox/hurtbox, трёхударную input-buffered комбинацию, damage, knockback, 0,4 с i-frames и combat events; базовые 0,55/0,65 с сверены с эталоном.

**Предыдущее обновление:** 21 июля 2026 — п. 34 выполнен: fixed-tick gameplay camera следует за player target через dead zones, поддерживает AABB parameter zones, FOV 70°, collision avoidance и единый camera snapshot для projection/culling/LOD.

**Предыдущее обновление:** 21 июля 2026 — п. 33 выполнен: C++ fixed-tick state machine связывает input, capsule movement и animation states idle/run/jump/fall/attack/hurt/death; damage recovery, invulnerability и terminal death покрыты unit-тестами.

**Предыдущее обновление:** 21 июля 2026 — п. 32 выполнен: клавиатура и Xbox/PlayStation-совместимые extended gamepad сведены в единые actions для gameplay и паузы; раскладки переназначаются и сохраняются, disconnect очищает состояние, reconnect восстанавливает handlers.

**Предыдущее обновление:** 21 июля 2026 — п. 31 выполнен и M3 закрыт: runtime-панель без пересборки переключает Metal wireframe, world-space collision overlay и object-ID раскраску; trigger/navmesh slots явно показывают отсутствие данных, HUD публикует CPU/GPU/frame/memory и scene counters.

**Предыдущее обновление:** 21 июля 2026 — п. 30 выполнен: collision payload включён в importer proof/ASTPAK, C++ capsule controller обрабатывает пол, стены, допустимые склоны, ступени, dynamic ground и checkpoint recovery; детерминированный маршрут проходит без провалов и останавливается у стены.

**Предыдущее обновление:** 21 июля 2026 — п. 29 выполнен: C++ runtime выполняет simulation с фиксированным шагом 1/60 s, ограничивает catch-up и предоставляет alpha для интерполяции render state; десятисекундный regression даёт 600 одинаковых ticks и сопоставимое состояние при 30/60/120 Hz.

**Предыдущее обновление:** 21 июля 2026 — п. 28 выполнен: добавлены animation sampling, hierarchical joint palette, four-weight skinning и Metal skinning path; материалы поддерживают normals, RGBA transparency/cutout, ambient/diffuse lighting, mip filtering и distance fog, а skin export сохраняет полную render geometry.

**Предыдущее обновление:** 21 июля 2026 — п. 27 выполнен: C++ runtime разрешает иерархию transforms, управляет резидентностью секций, выполняет frustum culling, material/LOD batching и первичный LOD; фоновой resource swap не блокирует render loop, moving-frustum regression на 381 mesh укладывается в frame budget.

**Предыдущее обновление:** 21 июля 2026 — п. 26 выполнен: Metal runtime загружает 381 mesh из локального ASTPAK, применяет scene transforms, depth buffer, базовый материал и ASTMTEX; profile-сверка подтвердила отображение Gaul-сцены при 60 FPS.

**Предыдущее обновление:** 21 июля 2026 — п. 25 выполнен: asset pipeline валидирует схемы, ссылки и диапазоны, возвращает структурированные ошибки и использует проверяемый content-addressed кеш; тест подтверждает пересборку только одного изменённого входа.

**Предыдущее обновление:** 21 июля 2026 — п. 24 выполнен: однокомандный pipeline детерминированно собирает ASTPAK с Metal-ready текстурами, mipmaps и импортированными ресурсами vertical slice.

**Предыдущее обновление:** 21 июля 2026 — п. 23 выполнен: принят собственный ASTPAK 1.0 с versioned header, canonical manifest schema, aligned payload, source-derived stable IDs и SHA-256; builder/reader проверены синтетическими тестами.

**Предыдущее обновление:** 21 июля 2026 — п. 22 выполнен и M2 закрыт: перспективная Metal-сцена с depth buffer отображается вместе с Flutter HUD; profile-проверка подтвердила стабильные 59,9–60,0 FPS и live CPU/GPU/memory counters.

**Предыдущее обновление:** 21 июля 2026 — п. 21 выполнен: ABI v1 связывает Dart и C++ через batch commands, bounded SPSC command/event queues, double-buffered UI snapshot и generated FFI bindings с реальным integration-тестом.

**Предыдущее обновление:** 21 июля 2026 — п. 20 выполнен: Objective-C++ renderer управляет command queue, resize, suspend/resume, sleep/wake, occlusion, ожиданием in-flight GPU work и идемпотентным stop/release.

**Предыдущее обновление:** 21 июля 2026 — п. 19 выполнен: Flutter game screen использует зарегистрированный macOS `AppKitView` с `MTKView`, drawable resize в физических Retina-пикселях и Flutter HUD поверх native view.

**Предыдущее обновление:** 21 июля 2026 — п. 18 выполнен: добавлены `engine/include`, `engine/src`, `engine/metal`, `engine/macos`, C++20 static target `AsterixEngine`, независимый XCTest target и universal-сборка Intel/Apple Silicon.

**Предыдущее обновление:** 21 июля 2026 — п. 17 выполнен: ADR-001 фиксирует границы Flutter/importer/C ABI/C++/Metal/macOS, ownership, thread model, versioned transport и полный native lifecycle.

**Предыдущее обновление:** 21 июля 2026 — п. 16 выполнен и M1 закрыт: `scripts/extract_slice_proof.sh` одной командой извлекает Gaul scene, PNG textures, animations/skins и PCM WAV с корневым manifest без ручной правки.

**Предыдущее обновление:** 21 июля 2026 — п. 15 выполнен: все 631 RWS классифицированы как Xbox IMA ADPCM; добавлены parser, tree inspection и декодирование первого segment в PCM WAV, формат и назначение потоков описаны в `documents/formats/rws.md`.

**Предыдущее обновление:** 21 июля 2026 — п. 7 выполнен: `documents/gameplay/slice_file_state_map.md` связывает menu/Gaul events с KWN/RWS, sector transitions и checkpoint classes; before/after saves зафиксированы hashes и byte-diff metadata вне Git, runtime-only состояния отделены от persistent save.

**Предыдущее обновление:** 21 июля 2026 — п. 6 выполнен: прямым чтением inventory, `LVL01.KWN`, sectors и class metadata составлен `documents/gameplay/content_catalog.md` для levels/sectors, персонажей, противников, интерактивов, RWS, cinematics и checkpoint; неподтверждённая семантика помечена явно.

**Предыдущее обновление:** 21 июля 2026 — п. 5 выполнен: в `documents/gameplay/reference_parameters.md` зафиксированы resolution, camera/FOV payload, нормализованные параметры движения и прыжка, боевые тайминги, damage/recovery диапазоны, методы, погрешности и уровни доверия.

**Предыдущее обновление:** 21 июля 2026 — п. 4 выполнен: прямым прохождением PC-версии подтверждены меню, загрузка, управление, камера, бой, смерть, checkpoint, пауза и первая штатная точка сохранения. Наблюдения, ограничения и хеши локального измерительного журнала зафиксированы в `documents/gameplay/reference_behavior.md`; оригинальные видео и save остались вне Git.

**Предыдущее обновление:** 21 июля 2026 — п. 3 выполнен: для vertical slice выбран Gaul Stage 1 от первого управления Астериксом до первой штатной точки сохранения после этапа.

**Предыдущее обновление:** 21 июля 2026 — п. 2 выполнен: добавлены защитные маски `.gitignore`, локальная проверка индекса и Git-истории, цель `make policy-check` и обязательный GitHub Actions workflow.

**Предыдущее обновление:** 21 июля 2026 — п. 1 выполнен: принята модель распространения «новый движок и локальный импортёр без оригинальных ресурсов»; решение зафиксировано в `documents/legal/resource_distribution_policy.md` и требует юридической проверки перед публичным релизом.

**Предыдущее обновление:** 21 июля 2026 — задачи сформированы из `flutter_macos_rewrite_plan.md`; текущий Flutter shell учтён как исходное состояние, но не закрывает M2 без встроенного Metal view.
