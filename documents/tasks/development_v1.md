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
| 75 | **Исключить проваливание Астерикса сквозь поверхность карты при движении:** заменить точечную проверку опоры под центром капсулы на устойчивое определение контакта по её footprint/траектории и проверить collision mesh на разрывы и неверные transforms на воспроизводимых участках | World collision | P0 | L | После п. 30 и 55; подтверждённая причина в runtime — после горизонтального шага `groundAt` проверяет одну точку, а проходимые треугольники исключены из obstacle resolution, поэтому промах на стыке/краю переводит капсулу в беспрепятственное падение; ниже `kill_y = -20` она штатно возвращается в checkpoint, который сейчас синтетически совпадает со стартом. Все проходимые маршруты Gaul сохраняют непрерывную опору с учётом радиуса капсулы, slopes, steps, triangle/sector seams и fixed-tick substeps; импортированные collision/transform данные проходят gap-аудит, fall recovery остаётся только для настоящего выхода за границы уровня и возвращает к корректному импортированному checkpoint; native route regressions воспроизводят найденные места провала |
| 76 | **Восстановить тени и затемнение внутри домов:** определить точный источник интерьерного освещения оригинала и перенести authored prelight/lightmap либо иной подтверждённый shadow path в asset pipeline и Metal renderer | Lighting fidelity | P0 | L | После п. 52; подтверждённый дефект pipeline — при RenderWare-флаге pre-lit импортёр пропускает `vertexCount × 4` байта RGBA, а ASTPAK/Metal их не получают; текущий shader использует только глобальный ambient и один направленный Lambert-свет без shadow/lightmap path. Аудит исходных mesh/material/extension данных устанавливает, достаточно ли vertex prelight или нужны дополнительные lightmap/lighting данные; выбранный механизм сохраняется без потери цвета/alpha, корректно комбинируется с texture/material lighting и даёт соответствующее оригиналу устойчивое затемнение внутри всех домов первого уровня без чрезмерного затемнения улицы; importer, renderer и indoor/outdoor visual regressions покрывают результат |
| 77 | **Провести и закрыть полный аудит non-skeletal FX первого уровня:** повторно извлечь все scene-node class IDs и их payload, включая 11 обнаруженных particle-node записей из локального proof, классифицировать enabled emitters, water/UV или texture-sequence данные, vertex/material/light animation и сопоставить каждый объект с ASTPAK и Metal draw path; для каждого неподдержанного механизма создать отдельный runtime/importer backlog item и исключить silent static fallback | Environment FX audit | P0 | M | После п. 72; машинно проверенный отчёт содержит object ID, section, source payload, animation mechanism, imported resource и renderer path для каждого объекта; ноль необъяснённых non-skeletal animated objects, а все остаточные пропуски имеют отдельные номера задач и visual/runtime regression criteria |
| 78 | **Исправить фактическую ASTPAK-интеграцию результатов п. 73 и повторно принять артефакты п. 74:** импортировать создаваемую level hook'ом водную поверхность вместо попытки назначить UV-профиль отсутствующим water texture bindings sector meshes, затем на одном свежем proof/ASTPAK проверить воду и передвигаемый каменный блок | Post-build asset acceptance | P0 | M | После п. 73 и 74; воспроизводимая сборка из локальной PC-копии доказывает, что sector meshes `tr_sabl_river_*` являются дном/берегами, а видимая поверхность приходит из level water hook. Importer извлекает hook, связанную geometry/material/texture и authored UV X/Y multipliers; ASTPAK audit на реальном пакете находит ненулевое число water surface bindings и Metal draw ranges, вода движется после холодного запуска и сохраняет фазу при pause/restore/streaming. Тем же пакетом повторно подтверждены scene object, transform, stone material/texture, collision и interaction bindings п. 74 до/после push; cache не скрывает изменения, установленный ASTPAK имеет ожидаемые hashes/counts, а visual regressions исключают статичную воду, старый металлический блок и смещённый collision |

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
- [ ] П. 75 — устранение провалов капсулы сквозь поверхность карты
- [ ] П. 76 — тени и интерьерное затемнение внутри домов
- [ ] П. 77 — полный аудит non-skeletal FX первого уровня
- [ ] П. 78 — реальная ASTPAK-интеграция воды и повторная post-build приёмка артефактов п. 74
- [x] П. 51 — реальные skeletal clips и полная 58-bone palette Астерикса
- [x] П. 52 — fidelity материалов и геометрии Gaul
- [x] П. 53 — visual regression запуска Gaul

---

**Последнее обновление:** 22 июля 2026 — п. 74 выполнен: `CKHkPushPullAsterix`, level nodes, парные stone meshes/materials и `CKFlaggedPath` ranges импортируются в ASTPAK; Metal использует authored transforms и единый fixed-tick offset для render/collision/interaction, а свежий локальный пакет подтвердил оба блока и texture `it_bloc2_01_mt` без металлического fallback.

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
