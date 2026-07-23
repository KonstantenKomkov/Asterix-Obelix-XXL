# Выполненные задачи первой итерации

## П. 84 — Полный runtime-профиль анимаций Астерикса

**Выполнено:** 23 июля 2026.

`asterix-player` расширен с восьми автоматических состояний до полного
биективного профиля всех 90 gameplay bindings. Оставшиеся 82 entry points
сохраняют точные имена исходных `heroAnimDict` slots и выбирают единственную
пару semantic action/variant без clip IDs в Metal или gameplay-коде. Профиль
охватывает idle/directional transitions, airborne/landing, combo/contextual
attacks, damage/recovery, interactions, ledge, water и swim.

Новый флаг `complete` заставляет registry и Metal отклонять пропущенный,
повторный, fallback или несовместимый с 58-node skin selector. Общий
`resolveRuntimeState` предоставляет строгий state/event entry point; loop,
phases, transitions и versioned fixed-tick animation events продолжают
разрешаться из binding data. Native event regressions проверяют low FPS,
loop-boundary, pause/restore и blend, а scoped tests — точные combat/swim
selectors и отказ неполного профиля.

Fresh gate подтвердил 345 clips / 518 slots / 408 bindings, из которых 90
concrete и 318 относятся к следующим п. 85–90; все unbound, unexplained,
unreachable и unknown counters равны нулю. SHA-256 отчёта:
`14dea84b3c60471c8a96d8b2217e9a9a47a3ffb85485c2217bd6310c688fec5f`.
Fresh/cached ASTPAK размером 68 665 972 байта совпал и имеет SHA-256
`bd42baca0be665b60deb61c03bdfcc868ef4743a873d48963eaf26a407e825c9`;
release-приложение собрано с установленным пакетом. Визуальные сопоставления
используют уже принятую task-62 side-by-side review metadata; оригинальные и
производные игровые данные в Git не добавлены. Прошли native XCTest,
`make check`, release build, resource policy и отдельное diff review. Описание:
[animation_binding_registry.md](../architecture/animation_binding_registry.md).

## П. 81 — Согласованное направление движения и ориентации Астерикса

**Выполнено:** 23 июля 2026.

Keyboard/gamepad actions используют положительное логическое значение forward,
но Gaul map-space идёт вперёд по `-Z`. Первичная реализация ошибочно пропустила
это преобразование и самосогласованно проверяла внутренний `+Z`, поэтому модель
смотрела верно, а capsule двигалась назад. Action vector теперь ровно один раз
преобразуется в map displacement `(x, 0, -z)`.

Player runtime вычисляет facing из фактического горизонтального capsule
displacement как `atan2(dx, -dz)` и предоставляет его render и combat. Поэтому
уже правильная ориентация модели и направления `←/→` не изменились, а `↑`
теперь перемещает capsule по `-Z`, `↓` — по `+Z`. Hitbox не переинтерпретирует
сырой input и сохраняет последнее направление в idle/attack. Camera follow
остаётся world-space consumer, а restore/respawn не меняют basis.

Fixed-tick regression принял четыре cardinal и четыре diagonal направления:
dot products map input `(x, -z)` → displacement, gameplay facing → displacement
и authored model forward → displacement больше `0,9999`; отдельные независимые
assertions требуют `↑ → -Z` и `↓ → +Z`. Дополнительные проверки покрывают
restore/respawn и одинаковые actions стрелок, WASD и gamepad. Release build и
cold start на свежем ASTPAK SHA-256
`bf8c3b4dddea50101ce913bd50d3539179d5da5dc48c52e355daf7615ea72b1b`
приняли последовательность `↑ → ← → ↓ → →`; локальные PNG и производные
игровые данные в Git не добавлены. Прошли native XCTest, `make check`, release
build, resource policy и отдельное diff review. Описание:
[game_input.md](../architecture/game_input.md).

## П. 80 — Data-driven composition render-ресурсов

**Выполнено:** 23 июля 2026.

Pipeline строит отдельный canonical `render-composition` ASTPAK resource из
подтверждённых actor/skin bindings и явных многослойных overrides. Аудит всех 38
экспортированных skins восстановил три составные chains: Asterix body 4 +
winged helmet 3, Obelix body 2 + costume overlay 1 и Roman leader body 28 +
equipment overlay 27. Всего свежий пакет содержит 42 однозначные compositions;
необъяснённых skins нет.

Metal runtime больше не выбирает жёстко заданные object IDs 3/4: он разрешает
`asterix/default/gameplay` из manifest, рисует body и шапку с собственными
материалами и общей 58-joint palette. Missing manifest/layer, повтор skin/role,
несовместимое число bones или несколько skins для одной semantic identity без
override дают контролируемую ошибку вместо marker/partial-model fallback.

Post-build gate принял representative Asterix, Obelix, NPC, enemy и mechanism
compositions. Debug cold start на свежем пакете подтвердил Asterix с крылатой
шапкой; локальные captures остались вне Git. Fresh/cached ASTPAK побайтно
совпали, SHA-256:
`bf8c3b4dddea50101ce913bd50d3539179d5da5dc48c52e355daf7615ea72b1b`.
Описание: [render_composition.md](../architecture/render_composition.md).

## П. 79 — Authored `CFogBoxNodeFx` первого уровня

**Выполнено:** 22 июля 2026.

Importer декодирует полный XXL1 class layout всех семи fog box: matrices,
effect name/type, координатные таблицы, RGBA/density stops и transition profile.
Каждый реальный payload потребляется точно до object boundary (ноль trailing
bytes) и сохраняется отдельным canonical `fog-volume` resource в ASTPAK.
Scene-node содержит единственный typed binding к ресурсу; прежние
`explicitly-disabled`/`backlogTask: 79` и static mesh fallback удалены.

Новый native runtime семплирует authored volumes в позиции gameplay-камеры,
смешивает цвет/плотность в Metal fragment path и обновляет переходы только по
fixed simulation clock. Regression проверяет точки внутри, снаружи и на
границе, pause, streaming residency и точный restore simulation time.
Malformed payload или binding отклоняются явно.

Свежая полная экстракция приняла 60 scene nodes, ровно 7 fog resources и ноль
неполных payload, invalid bindings или необъяснённых non-skeletal mechanisms.
ASTPAK размером 68 646 836 байт имеет SHA-256
`5da692131bde3c534b8668a4660f1ab34f2881ac0eec506fa7fd4ec5d605d3e4`.
Итоговый environment-FX audit имеет SHA-256
`03f0fb2a03e4d83ac0c21b978bccea7a241d84b5ff958eaf4f3441b22a1c8b25`.
Исходные и производные игровые данные в Git не добавлялись. Описание:
[environment_fx_audit.md](../architecture/environment_fx_audit.md).

## П. 77 — Полный аудит non-skeletal FX первого уровня

**Выполнено:** 22 июля 2026.

Importer сохраняет полный raw payload каждой sector scene-node: byte length,
длину декодированного префикса, SHA-256 и hex. Свежая экстракция классифицировала
60 объектов классов 2, 3, 9, 19, 21 и 26 во всех пяти секциях. Вместо ожидаемых 11 обнаружены и
проверены 12 enabled `CParticlesNodeFx`: 11 в `STR01_00` и один в `STR01_03`.
Все они сопоставлены с точными ASTPAK environment-FX resources и Metal
camera-facing transparent particle path.

Level hooks дали три принятых material UV-scroll draw ranges. Texture sequence,
vertex/material/light animation не обнаружены; 27 `CAnimatedNode` явно
классифицированы как skeletal frame hierarchy, а 668 prelit mesh — как authored
static lighting. Итог: ноль неполных source payload captures, invalid bindings
и необъяснённых non-skeletal animated objects.

Семь объектов класса 26 идентифицированы как неподдержанные `CFogBoxNodeFx` и
вынесены в п. 79 с runtime/visual regression criteria. До реализации pipeline
оставляет их без mesh payload с явными `fog-volume`, `explicitly-disabled` и
`backlogTask: 79` metadata, исключая silent static fallback.

Машинный отчёт имеет SHA-256
`4cb827f5f9c434f776e39bc4379ad17d5f5cb9d024e21b14882e00037113a387`.
Свежий установленный ASTPAK размером 68 580 276 байт имеет SHA-256
`7e46ccc9cae765e6467bac82ceefd691f556388fa591ab115e08a1973a297644`;
общий post-build gate также принял water, collision, checkpoint, push/pull и
668 authored-lighting bindings. Описание:
[environment_fx_audit.md](../architecture/environment_fx_audit.md). Исходные
payload, отчёт и производные игровые ресурсы в Git не добавлялись.

## П. 76 — Authored тени и интерьерное затемнение домов Gaul

**Выполнено:** 22 июля 2026.

Точный исходный механизм подтверждён без эвристик по именам: все 668 static
geometry первого уровня имеют RenderWare `rpGEOMETRYPRELIT` (`flags & 0x08`) и
хранят RGBA по четыре байта на вершину. Importer теперь сохраняет 132 268
нормализованных RGBA вместе с geometry object ID, scene-node transform,
triangle material slot и texture binding. Pipeline требует точного совпадения
vertex counts и конечных каналов `0…1`; cache version повышена.

Metal переносит prelight в vertex buffer, интерполирует и модулирует им
texture/material RGBA с сохранением authored alpha и cutout/blended path.
Поскольку prelight уже является результатом RenderWare fixed-function lighting,
повторный Lambert для таких mesh отключён; non-prelit geometry сохраняет прежний
ambient + directional Lambert и нейтральный RGBA. Runtime отклоняет malformed
или неполный authored payload вместо silent global-light fallback.

Cold-start review обнаружил старый пропуск п. 75: package не содержал
level-local collision пола дома под реальным checkpoint. В pipeline добавлены
13 ground и 62 dynamic-ground mesh из `LVL01.KWN`; итоговые 287 collision mesh /
10 558 triangles разрешают checkpoint на authored floor без синтетического
spawn. Indoor cold start проверен локальным capture; alpha/cutout и
pause/restore/streaming остаются в общих material/runtime regressions, а
машинный audit охватывает authored lighting всех sector mesh, включая улицу.
Изображения и игровые данные в Git не добавлялись.

Post-build gate принял 668 lighting bindings / 132 268 vertices / 668 material
draw ranges, RGB range `0…1`, ноль invalid bindings и payload hashes. Clean и
полностью cached ASTPAK побайтно совпали: 68 578 756 байт, SHA-256
`0d6bcaf988d3f84086290757fa0d46c6d8d3dcf88b606a83f6b4c6614372c56c`.
Описание: [authored_lighting.md](../architecture/authored_lighting.md). Прошли
`make check`, native XCTest, cold-start debug build, resource policy и отдельное
diff review.

## П. 75 — Устойчивый контакт капсулы с поверхностью Gaul

**Выполнено:** 22 июля 2026.

Причина провалов устранена в collision runtime: вместо единственного `groundAt`
под центром контроллер проверяет центр и 12 точек кругового footprint радиуса
капсулы на каждом fixed-tick substep. Сохранились ограничения slope/step и
obstacle resolution; межтреугольные и межсекторные seam больше не переводят
капсулу в свободное падение. Native routes покрывают общий triangle edge,
зазор 0,18 world unit между sector objects, slope, step, moving ground и
состояния до/после настоящего выхода ниже `kill_y`.

Importer читает единственный level `CKHkAsterixCheckpoint` (2/193), сохраняет
все девять исходных references и разрешает scene node 23 до world position
`(63,5; 3,2; 78,2)`. Pipeline упаковывает отдельный typed checkpoint payload,
Metal требует его при cold start и привязывает fall recovery к скорректированной
collision-позиции; прежний эвристический spawn по ближайшему треугольнику удалён
из package runtime. Cache version повышена.

Post-build gate прочитал свежий установленный ASTPAK и принял четыре sector
collision payload: 212 meshes / 9423 triangles, source/object IDs, hashes и
transforms без invalid binding. Clean и полностью cached builds побайтно
совпали: 59 863 108 байт, SHA-256
`0c8c826c2e9faea380c56b6ab7e4f35abd1b739b2ec25766ae37d1df97ade631`.
Release cold-start smoke с этим пакетом прошёл без loader/runtime error.
Архитектурное описание обновлено в
[world_collision_capsule.md](../architecture/world_collision_capsule.md).
Прошли `make check`, 53 native XCTest, macOS release build, resource policy и
отдельное diff review; ASTPAK и исходные/производные игровые ресурсы не добавлялись.

## П. 78 — Реальная ASTPAK-интеграция воды и повторная приёмка push/pull-блоков

**Выполнено:** 22 июля 2026.

Дефект п. 73 подтверждён на локальной PC-копии: sector meshes
`tr_sabl_river_*` являются дном/берегами и не содержат water texture bindings.
Видимую поверхность создают два level hook `CKHkWaterFall`, связанные с branch
nodes 108/109 и geometry 44–46. Importer теперь извлекает эти три поверхности
(449 vertices, 628 triangles), их transforms, материалы `sfx_riviere` /
`a_tr_eau_mer_f01_p0`, textures и authored UV-множители `(0,3; 0,6)` /
`(1,0; 0,5)` в отдельный proof artifact. Неявная маркировка sector materials
удалена, поэтому статические берега больше не могут стать water fallback.

Pipeline создаёт три level mesh/scene-node bindings и три Metal material draw
ranges с `uv-scroll` от simulation time. Существующая native visual regression
подтверждает движение после холодного старта и сохранение фазы при pause,
restore и streaming. Cache version повышена: clean, первый cached и полностью
cached builds дали идентичный ASTPAK размером 59 862 260 байт и SHA-256
`5d564cc01a63a683f505beb7b9654cd4eca09721ed312f75566184e925e1cb9b`.

Новый post-build `audit-slice-assets` проверяет payload готового пакета и принял
3 water surface bindings / Metal draw ranges, 628 water triangles, два texture,
ноль invalid/sector fallback. Тем же установленным ASTPAK повторно приняты оба
`push-pull-stone` scene object и по два render/collision/interaction binding,
authored transforms/ranges и единственный каменный texture `it_bloc2_01_mt`;
native regression покрывает состояния до/после push и restore. Пакет установлен
в стандартный Application Support, исходные и производные ресурсы остались вне
Git. Прошли 98 Flutter tests, 51 native XCTest, `flutter analyze`, macOS debug
build, resource-policy gate и отдельное diff review.

## П. 74 — Каменный push/pull-блок первого уровня

**Выполнено:** 22 июля 2026.

Источник дефекта установлен в level bindings: два `CKHkPushPullAsterix` ведут к
nodes 8 и 11 с authored positions `(-7.820352, 3.079212, -5.310643)` и
`(-27.091726, 1.089171, 49.158550)`. Geometry самого node — узкая служебная
металлическая деталь `spec1_meta_bloc2_01_p0`; видимые парные meshes 17/24
содержат каменный куб (175 vertices, 118 triangles) и material/texture
`it_bloc2_01_mt`. Importer теперь извлекает именно эту проверенную пару и
отклоняет металлический visual fallback.

Pipeline сохраняет полный transform, origin, axis и исходные `CKFlaggedPath`
ranges `0…11.863387` / `0…8.612516`. Metal и fixed-tick interactive runtime
используют единый offset для render vertices, collision volume и push-сценария;
поперечное проникновение блокируется, checkpoint/save восстанавливают позицию,
а старые saves мигрируют к нулевому offset.

Создан свежий локальный proof и ASTPAK размером 59 798 292 байта, SHA-256
`74d1864eae2ba30491cd7ad9905d4ed365c6b54cc139936a3ff0f30e869d91d7`: пакет содержит
оба `push-pull-stone` object/resource binding, level texture 128×128
`it_bloc2_01_mt` и исходные transforms; артефакт и извлечённые ресурсы остались
вне Git. Архитектурное описание: [push_pull_stone.md](../architecture/push_pull_stone.md).
Pipeline/native regressions фиксируют material и transform до push, движение
вдоль authored path, collision поперёк него, состояние после push и restore.
Прошли `make check`, native XCTest, macOS debug build, diff review и resource
policy.

## П. 71 — Бег по умолчанию при старте gameplay

**Выполнено:** 22 июля 2026.

Причина неверного gait локализована в `player::Runtime` и не зависит от уровня,
spawn-сценария или animation registry: acceleration-based классификация
оставляла первые fixed ticks полного ввода ниже run threshold, из-за чего запуск
визуально начинался ходьбой. Gameplay locomotion теперь сразу принимает
эталонные 4,32 world unit/s (2,4 H/s) и публикует `run`; аналоговый magnitude
сохраняется, диагональ нормализуется, а collision-limited displacement
по-прежнему определяет фактическую фазу анимации.

Ходьба отделена от gameplay явным `LocomotionMode::scripted_walk` с authored
скоростью 1,8 world unit/s. Возврат управления переводит runtime обратно в
`gameplay`; respawn и restore также сбрасывают только в безопасный gameplay
mode. Удалена неявная hysteresis-классификация, которая могла повторно включить
walk без cinematic/scripted-команды.

Native regression повторяет чистый старт Gaul и контрольный collision-сценарий
с независимым object id, затем проверяет gameplay → scripted walk → gameplay,
немедленный выбор эталонной скорости после возврата управления и respawn.
Отдельное diff review подтвердило независимость от level data и устранило
оставшиеся неиспользуемые gait thresholds. Пройдены 49 native XCTest, resource
policy, native FFI build, `flutter analyze` и все 92 Flutter tests. Оригинальные
ресурсы и производные игровые данные в Git не добавлялись.

## П. 70 — Collision-safe следование gameplay-камеры

**Выполнено:** 22 июля 2026.

Точечный segment test заменён на swept-volume collision. Объём камеры —
консервативная сфера с радиусом не меньше конфигурируемого collision radius и
диагонали near plane, вычисленной из FOV, near distance и aspect ratio.
Conservative advancement по минимальному зазору до triangle world не
перескакивает тонкие поверхности и устойчиво обрабатывает вырожденные
треугольники.

Runtime сначала ограничивает путь target → smoothed candidate, затем отдельно
проверяет lateral путь от предыдущего к текущему fixed-tick snapshot. Поэтому
весь отрезок, используемый Metal render interpolation, остаётся collision-safe
в углах и при поперечном следовании. После исчезновения контакта камера
возвращается к desired distance прежним exponential smoothing без скачка.

Native regressions воспроизводят near-plane clearance у тонкой стены, lateral
follow в углу, промежуточные render snapshots и плавный возврат после потери
контакта. Diff review заменило дискретное семплирование пути на conservative
advancement и добавило degenerate-triangle fallback. Пройдены 48 native XCTest,
resource policy, native FFI build, `flutter analyze` и все 92 Flutter tests.
Оригинальные ресурсы и производные игровые данные в Git не добавлялись.

## П. 61 — Следование gameplay-камеры за игроком

**Выполнено:** 22 июля 2026.

Gameplay camera подключена к актуальной позиции capsule controller внутри
каждого fixed tick. Camera runtime хранит предыдущий и текущий снимки и выдаёт
интерполированный snapshot по render alpha; Metal render loop использует один
и тот же снимок для view/projection, frustum culling, LOD camera distance и
пространственного audio listener, исключая межсистемный рассинхрон.

Regression-тест совместно прогоняет capsule controller, player runtime и
камеру при движении в четырёх направлениях, проверяя заданную dead zone и
непрерывность промежуточных кадров. Отдельный тест подтверждает сохранение
collision-limited follow перед препятствием. Diff review подтвердило единый
render snapshot и отсутствие обходных camera transforms.

Пройдены 45 native XCTest, resource policy, native FFI build, `flutter analyze`,
все 92 Flutter tests и release-сборка macOS. Оригинальные ресурсы и производные
игровые данные в Git не добавлялись.

## П. 69 — Сквозная приёмка полноты привязок анимаций

**Выполнено:** 22 июля 2026.

Добавлен воспроизводимый acceptance gate, который повторно проверяет строгий
локальный каталог 345 clips / 52 dictionaries / 518 slots и соединяет каждый
clip по точному `NNNN.animation.json` со всеми versioned bindings. Для всех 408
actor/action/context bindings отчёт выводит проверенный путь выбора из hero
graph, renderer compatibility state machine, character state/event graph,
world event profile либо cinematic script event/cue. Итоговые значения
unbound, unexplained, unreachable и unknown clips равны нулю.

Три representative sequences — locomotion/combat Астерикса, machinegun
fire/recoil и cinematic scene-data-1 — зафиксированы versioned metadata и
разрешаются в точные bindings после side-by-side сверки с локальным оригиналом.
Подробный JSON-отчёт сохранён вне Git с SHA-256
`788767f3cdab72bbdd673df41b64b0204a12663e272a406e8d3b2e7cac42bbcd`;
каталог сохранил SHA-256
`3f42b0ee77fe59609c93a28adcf42d1f4e17a5f9814b383d0c1528c2afa4fbbc`.

Отдельное diff review выявило и устранило ложное принятие всех hero bindings
по одному лишь наличию entry state: итоговая проверка явно обходит transitions
обоих достижимых hero-компонентов. Добавлены негативные regressions для
неполного graph manifest и неизвестного visual binding. Пройдены resource
policy, `flutter analyze`, все 92 Flutter tests и повторный локальный acceptance
gate. Оригинальные clips, captures и производные игровые ресурсы в Git не
добавлялись.

## П. 68 — Единые animation events и синхронизация gameplay

**Выполнено:** 22 июля 2026.

В versioned binding manifest добавлен `eventTrackVersion: 1` и типизированные
tracks для locomotion, combat, hurt и world state. Footsteps, hit/hurt windows,
impulses/root motion, object state commits, VFX/SFX, camera cues и явное
завершение one-shot теперь описываются нормализованными фазами clips. Validator
отклоняет неизвестные bindings и event types, дубли, неупорядоченные фазы и
one-shot без completion.

Нативный fixed-tick sampler использует абсолютную фазу и интервал
`(previous, current]`, перечисляет все пересечённые loop и формирует устойчивый
identity `track:instance:loop:event`. Поэтому low FPS не теряет события на
границе loop, обе ветви blend не дублируют side effects, pause не продвигает
курсор, а checkpoint restore продолжает сохранённый instance/phase без replay.
Отдельное diff review обнаружило и исправило доставку событий на фазе `0.0`.

Пройдены resource policy, native FFI build, `flutter analyze`, все 89 Flutter
tests и 43 native XCTest. Оригинальные ресурсы и производные игровые данные в
Git не добавлялись.

## П. 67 — Scripted/cinematic animation timelines

**Выполнено:** 22 июля 2026.

Versioned binding registry расширен 14 independently addressable scene-data
timelines, которые связывают все подтверждённые 63 cinematic contexts и 44
уникальных clips с точными script events, actor actions, dictionary slots и cue
indices. Entrance, exit и in-game типы, camera/audio/subtitle cues, блокировка и
возврат управления, interrupt, skip, checkpoint restore и повторный вход имеют
явные политики. Не подтверждённое исходными данными распределение 14
`CKCinematicSceneData` между четырьмя `CKCinematicScene` не угадывалось.

Добавлены идемпотентный генератор, строгая проверка totals, уникальности
timelines/events и exact event-to-clip reachability. Native coordinator
синхронно выдаёт actor tracks и presentation cues, сохраняет текущий cue при
interrupt, восстанавливает snapshot без replay, применяет terminal state при
skip и всегда возвращает gameplay camera/audio/control. Сценарный XCTest
проверяет двух actors, interrupt/resume, checkpoint restore, skip и re-entry;
Dart regressions проходят все 63 bindings и отклоняют неполные graphs.

Пройдены resource policy, native FFI build, `flutter analyze`, все 88 Flutter
tests и 41 native XCTest. Генератор повторно создаёт byte-identical manifest;
оригинальные ресурсы и производные игровые данные в Git не добавлялись.
Sub-frame animation event tracks остаются п. 68.

## П. 66 — World animation graphs объектов, окружения и механизмов

**Выполнено:** 22 июля 2026.

Versioned binding registry расширен 13 exact world/UI/FX profiles, которые
покрывают все подтверждённые 45 clips и 46 dictionary contexts machinegun,
двух shop, activator, mechanism component, трёх turtles, checkpoint, wild boar,
lightning FX и двух interface dictionaries. Каждый context получил конкретный
world/state/UI/environment trigger, loop policy, допустимые transitions,
root-motion policy и нормализованные phases; общий shop clip сохраняет обе
независимые привязки.

Добавлен идемпотентный генератор graph из локального каталога п. 62.5 и строгая
валидация profile isolation, event targets, trigger presence, достижимости,
skeleton compatibility и totals. Native world-animation runtime принимает
монотонные persistent event sequence IDs, игнорирует повторные и устаревшие
события и восстанавливает сохранённый action напрямую по политике
`snapshot-without-replay`, не повторяя activate/break/collect/respawn side
effects.

Regressions проверяют все 46 runtime triggers / 45 clips, повторную доставку,
save/checkpoint restore и malformed graphs. Пройдены `flutter analyze`, все 86
Flutter tests, 40 native XCTest и resource-policy gate. Генератор повторно
создаёт byte-identical manifest; оригинальные ресурсы и производные игровые
данные в Git не добавлялись. Детальная fixed-tick доставка animation event
tracks остаётся п. 68.

## П. 65 — Animation graphs врагов, NPC и персонажей

**Выполнено:** 22 июля 2026.

В versioned binding registry добавлены 27 exact actor/skin/costume profiles:
25 character dictionaries и два сохранённых shared cinematic context. Graph
покрывает все подтверждённые 92 clips и 109 membership contexts basic enemies,
leaders, NPC и animated characters. Для каждого профиля зафиксированы entry,
полный required action set, допустимые transitions, runtime state/event
bindings, trigger, loop policy, root motion и нормализованные phases.

Enemy runtime публикует semantic actions для idle, pursuit/return, attack,
hit/stun/knockback и death; spawn/perception, despawn и special действия
представлены явными event triggers. Variant selector детерминирован stable seed
и номером actor-local перехода. Gameplay impact `0,25 / 0,65` совпадает с
точной attack animation phase; death остаётся terminal. Отдельный идемпотентный
generator воспроизводит graph из локальных артефактов каталога 62.4.

Validator и regressions проверяют exact profile isolation, полноту totals,
достижимость всех actions, отсутствие cross-profile transitions, skeleton
compatibility, детерминированный выбор вариантов и соответствие AI states.
Пройдены `flutter analyze`, все Flutter tests, native XCTest и resource-policy
gate. Оригинальные ресурсы и производные игровые данные в Git не добавлялись;
расширенная fixed-tick доставка versioned event tracks остаётся п. 68.

## П. 64 — Полный animation graph управляемых героев

**Выполнено:** 22 июля 2026.

Versioned binding manifest расширен до полного actor-local graph всех 183
подтверждённых hero clips LVL01: 90 Астерикса, 71 Обеликса и 22 Идефикса.
Locomotion, directional transitions, jump/fall/landing, attack/combo,
hurt/launch/tumble/recovery/death, interactions, ledge и water/swim actions
получили точные actor, skin, costume, action, variant, playback, root-motion и
transition bindings. Исходный каталог подтверждает только costume `default`,
поэтому неподтверждённые costume-specific fallback не создавались.

Добавлены `graphVersion`, actor entry states, полный required-action audit,
проверка actor-local переходов и достижимости каждого действия. Runtime
детерминированно выбирает clip variant и публикует нормализованные фазы
cycle/contact, windup/impact/recovery, reaction/recovery и commit/complete;
полный versioned event-track transport остаётся отдельным п. 68. Семь прежних
алиасов Астерикса сохранены для Metal renderer и указывают на те же
подтверждённые clips без clip IDs в коде.

Автоматические regressions фиксируют 183 уникальных clips, размеры graph
90/71/22, полную достижимость, детерминированный выбор, phase crossings,
переходы idle → run → death и совместимость representative pose sequences с
58/58/31-node skeleton palettes. Пройдены resource policy, native FFI build,
`flutter analyze` и все 82 Flutter tests. Отдельное diff review исправило
первоначально слишком узкие locomotion transitions и добавило reachability
gate. Оригинальные ресурсы и локальные review-артефакты в Git не добавлялись.

## П. 60 — Эталонная скорость бега Астерикса

**Выполнено:** 22 июля 2026.

Повторная покадровая сверка локальных Take C2/C3 отделила переходные и
низкоскоростные фазы от устойчивого бега при полном вводе. Runtime теперь
переводит эталонные 2,4 H/с через высоту collision capsule `1 H = 1,8` world
unit: `run_speed` равен 4,32 world unit/s, acceleration — 18,0, deceleration —
21,6. Snapshot публикует hysteresis gait `idle/walk/run`; полный ввод достигает
run и воспроизводит подтверждённый clip 0035 с исходным периодом 0,56 с, а
диагональ сохраняет ту же длину маршрута.

Контрольный fixed-tick маршрут 10 H / 18 world units проходится из idle за
4,20–4,40 с. Тесты фиксируют скорость, gait-пороги, cadence с допуском 0,04
цикла, диагональную нормализацию и визуальное замыкание бегового цикла. Прошли
38 native XCTest, все 78 Flutter tests, `flutter analyze`, debug macOS build и
resource-policy gate. Оригинальные видео, кадры и игровые ресурсы в Git не
добавлялись.

## П. 63 — Data-driven реестр привязок анимаций

**Выполнено:** 22 июля 2026.

Добавлен versioned manifest `assets/animation_bindings.v1.json`. Текущие семь
достижимых gameplay states Астерикса описаны ключами actor, точного skin,
costume, action/event, variant и context; рядом хранятся loop policy, priority,
fallback, skeleton nodes и допустимые transitions. Номера clips удалены из
renderer/state machines и остаются только данными manifest.

Extractor переносит manifest в локальный proof, pipeline валидирует схему,
обязательные states, уникальность, переходы, наличие clip и совместимость
skeleton, затем добавляет ресурс `animation-bindings` в ASTPAK. Runtime повторно
разрешает точный профиль и возвращает диагностируемую ошибку для неизвестной,
неоднозначной или несовместимой привязки вместо случайной pose; loop policy
передаётся sampler из binding.

Добавлены unit и pipeline regressions, архитектурная документация и полная
macOS build-проверка. Пройдены `flutter analyze`, все Flutter tests, native
XCTest, debug app build и resource-policy gate. Оригинальные ресурсы и
производные игровые данные в Git не добавлялись. Полное расширение registry на
остальные hero actions остаётся п. 64, на остальных actors/world/cinematics —
п. 65–67, event tracks — п. 68.

## П. 62.7 — Финальная машинная приёмка семантического каталога

**Выполнено:** 22 июля 2026.

Добавлен отдельный dataset-specific acceptance gate для LVL01, который фиксирует
объективные размеры набора и принимает ровно 345 manager clips, 52 animation
dictionaries и 518 структурных slots. Обратная проверка slot coverage закрывает
пробел прежнего валидатора: каждый из 449 заполненных slots обязан быть
представлен ровно одним объективным membership, а существующая semantic
проверка требует для него ровно один confirmed context.

Итоговый локальный каталог
`$HOME/asterix-reference/animation-catalog-cinematics-task62.6.json` (SHA-256
`3f42b0ee77fe59609c93a28adcf42d1f4e17a5f9814b383d0c1528c2afa4fbbc`)
успешно прошёл gate: все 345 clips имеют статус `confirmed`, обязательные
semantic поля и evidence; `unreviewed`, `provisional`, `excluded`, пустых
обязательных значений, потерянных memberships и лишних contexts нет.

Пустые dictionary slots входят в объективные 518 структурных позиций, но не
получают вымышленных animation contexts. Импортированные animation payload не
содержат authored event tracks, поэтому подтверждённые `events: []` остаются
явным ограничением до versioned gameplay event tracks п. 68. Оригинальные
ресурсы и производные игровые данные в Git не добавлялись.

## П. 62.6 — Семантический каталог cinematic dictionaries и shared contexts

**Выполнено:** 22 июля 2026.

Разобраны все 14 dedicated cinematic dictionaries LVL01 (`3`, `5–16`, `18`):
63 заполненных slots и 44 уникальных clips. Каждый slot получил отдельный
context с actor/prop profile, `CKCinematicSceneData` owner, scene-data timeline
membership, scripted action, playback, transitions и root-motion policy.
Dictionary `0`, дополнительно заимствованный scene data 10, сохранён как
gameplay dictionary Идефикса; его scene-specific роли представлены dedicated
dictionaries `8` и `18` и не подменяют владельца gameplay slots.

Shared clips Астерикса, Обеликса, Идефикса и animated-character dictionaries
сохраняют все исходные gameplay/scripted contexts и получают отдельные
cinematic contexts для точных dictionary slots. Конкретные сюжетные названия не
угадывались при отсутствующем event-to-scene mapping: timeline evidence
ограничено типизированной ссылкой scene-data owner и фактическим membership.
Импортированные payload не имеют отдельного authored event track, поэтому
`events: []` сохранён без предположительных cues.

Добавлены воспроизводимый генератор cinematic annotations, версионированный
scope и отдельная команда проверки. Локальные производные артефакты вне Git:
`animation-semantics-cinematics-task62.6.json` (SHA-256
`c3d924f2c3efb6ed85b2e6e38a572e98cdf16ad153f062a0af358ee93cc36d42`) и
`animation-catalog-cinematics-task62.6.json` (SHA-256
`3f42b0ee77fe59609c93a28adcf42d1f4e17a5f9814b383d0c1528c2afa4fbbc`). Scoped
и полный валидаторы принимают результат; полный каталог уже содержит 345 confirmed clips, но
формальная проверка всех 518 структурных slots остаётся п. 62.7. Оригинальные
ресурсы и производные игровые данные в Git не добавлялись.

## П. 62.5 — Семантический каталог анимаций мира, UI и FX

**Выполнено:** 22 июля 2026.

Разобраны все 13 world-scope dictionaries LVL01: machinegun, два shop,
activator, mechanism component, три square turtle, checkpoint, wild boar,
lightning FX и два interface dictionaries. Подтверждены 46 заполненных slots,
45 уникальных clips и отдельный semantic context для каждого slot, включая два
контекста общего shop clip `0321`.

Для каждого context зафиксированы owner, skin profile, world action/event,
playback policy, transitions, root-motion policy и evidence типизированной
owner reference, slot membership, pose review и transform analysis. Проверка
импортированных payload подтвердила отсутствие отдельного authored event track;
это представлено явным `events: []`, а не предположительными gameplay cues.

Добавлены воспроизводимый генератор world annotations, версионированный набор
world dictionary IDs и отдельная команда scoped validation. Локальный каталог
`$HOME/asterix-reference/animation-catalog-world-task62.5.json` проходит
проверку всех world/UI/FX dictionaries, не требуя преждевременной классификации
cinematic dictionaries п. 62.6. Оригинальные ресурсы и производные игровые
данные в Git не добавлялись.

Ограничение: конкретные runtime cues и синхронизация gameplay/VFX будут
оформлены отдельными versioned event tracks в п. 68; cinematic/shared contexts
остаются в scope п. 62.6.

## П. 62.4 — Семантический каталог анимаций персонажей

**Выполнено:** 22 июля 2026.

Разобраны все 25 character dictionaries LVL01: общий словарь 18 basic enemies,
два словаря leaders и 22 dictionaries NPC/animated characters. Подтверждены 92
уникальных clips и ровно 109 membership contexts; каждый slot сохраняет owner,
dictionary-specific HAnim skin profile, costume, action/state family, playback,
variant, transitions, authored root motion и сведения об events.

Enemy и leader slots распределены по spawn/awareness, locomotion, combat,
damage, death и special families. Одноразовые `CKHkAnimatedCharacter`
dictionaries отмечены как scripted performances с сохранением их object/dict
identity; привязка к конкретным cinematic timelines оставлена п. 62.6. В
импортированных skeletal payload нет отдельного event track, поэтому events не
подменены предположительными gameplay hit windows.

Добавлены воспроизводимый генератор character annotations и отдельный scoped
validator, который исключает boars, turtles, mechanisms, UI и FX будущего
world-scope. Производные игровые данные сохранены только локально вне Git:
`animation-semantics-characters-task62.4.json` (SHA-256
`e49e9cbe24089c29a2d6c639e3cd5c54bb3e8a860914f27199fd28b9e1726cb1`) и
`animation-catalog-characters-task62.4.json` (SHA-256
`fca2839152a20ea85eed7551e572a3328c6536e1e09fb666c7c7520ff85c37cc`).

## П. 62.3 — Семантический каталог анимаций Обеликса и Идефикса

**Выполнено:** 22 июля 2026.

Все 84 занятых slots `CKHkObelix.heroAnimDict` сведены к 71 уникальному clip,
а 44 slots `CKHkIdefix.heroAnimDict` — к 22 clips; каждый clip получил статус
`confirmed`. Для обоих героев зафиксированы default costume, точные
`CKSkinGeometry:2` и `CKSkinGeometry:0`, действие, playback, переходы, authored
root motion и отсутствие отдельного event track в импортированном payload.

Общие hero slot families сопоставлены с уже подтверждённым словарём Астерикса
и отдельно проверены семикадровым front/side exact-skin просмотром. Уникальные
слоты Обеликса 64–65 просмотрены отдельно и классифицированы как recovery и
airborne-stun. Геометрия Идефикса хранит skin weights без собственной копии
HAnim hierarchy; reviewer использует явно указанный hierarchy object 1 и
проверяет его против `skin.boneCount`, не подменяя выбор точной geometry или
иерархии совпадением числа костей clip.

Помимо 128 gameplay memberships описаны все 17 shared/cinematic contexts, то
есть итог содержит ровно 145 contexts без потери actor или scripted назначения.
Производные игровые данные сохранены только локально вне Git:
`animation-semantics-obelix-idefix-task62.3.json` (SHA-256
`212274d1154543180670905d60be0e0dac1eb63f31523bb74327244b447aa446`) и
`animation-catalog-heroes-task62.3.json` (SHA-256
`bfe810f43e5f5b9150f20524cf8ee66e8c3522a46143449cad5f310533d2fb1`).
Совместный scoped validator принимает dictionaries 0 и 1 независимо от ещё
незавершённых словарей, сохраняя обязательное покрытие shared contexts.

## П. 62.2 — Семантический каталог анимаций Астерикса

**Выполнено:** 22 июля 2026.

Все 108 занятых slots `CKHkAsterix.heroAnimDict` сведены к 90 уникальным clips
и получили статус `confirmed`. Для каждого clip зафиксированы exact skin
`CKSkinGeometry:4`, default costume, наблюдаемое действие и семейство вариантов,
loop/one-shot policy, допустимые переходы, authored root motion и отсутствие
отдельного event track в импортированном animation payload.

Семантика подтверждена семикадровым front/side exact-skin просмотром, анализом
motion-root node 1, структурой track и типизированной ссылкой владельца словаря.
Помимо 108 gameplay memberships отдельно описаны все 10 shared cinematic
memberships в dictionaries 5, 12 и 14 с владельцами `CKCinematicSceneData`
objects 1, 8 и 10. Таким образом, итог содержит ровно 118 contexts без потери
actor или назначения общего clip.

Производные игровые данные сохранены только локально вне Git:
`animation-semantics-asterix-task62.2.json` (SHA-256
`79f5c0718fdb7bd228ed3ec37ba728681acb5a2858a735d784cb3d2f5adfa767`) и
`animation-catalog-asterix-task62.2.json` (SHA-256
`881d60e63785ec0cf2477b3a7d81b9992714df56d9c17c81a548436705e0c5b6`).
Scoped validator принимает dictionary 2 независимо от ещё незавершённых
словарей, но по-прежнему требует все shared contexts. Профильные и полные
Flutter-тесты, статический анализ, resource policy и diff review проходят.

## П. 62.1 — Инфраструктура полного семантического каталога анимаций

**Выполнено:** 22 июля 2026.

Импортёр извлекает все 52 `CAnimationDictionary`, нормализует 518 slots и
доказывает структурное покрытие всех 345 manager clips. По точным serialized
object references и layouts XXL-Editor каждый словарь связан с владельцем;
сырые числовые совпадения отделены от типизированных и явно generic полей.

Добавлены воспроизводимый draft каталога, отдельный слой ручных annotations,
строгий валидатор и HTML reviewer с семикадровой выборкой, фильтрацией и
сортировкой по dictionary slots. Аннотации не могут менять объективные поля.
Финальный статус требует отдельный semantic context для каждого membership:
один track, общий для gameplay и cinematic dictionaries, нельзя подтвердить
только по одному известному использованию. Локальный LVL01-каталог и игровые
ресурсы остаются вне Git.

Профильные тесты покрывают extraction, повреждённые slots/references,
защищённое слияние annotations и точное покрытие contexts. Полный `make check`,
статический анализ, Flutter-тесты, resource policy и diff review проходят.

## П. 59 — Locomotion-анимации Астерикса

**Выполнено:** 22 июля 2026. **Повторно исправлено после визуального runtime-ревью:** 22 июля 2026.

Первые две реализации ошибочно назначали состоянию `run` файлы `0055`, а затем
`0054`: второй клип оказался наклоном/поворотом, а не бегом. Дополнительно не
включался начальный keyframe каждого RenderWare bone track. Разбор hero animation
dictionary исходного уровня и покадровая проверка при зажатом движении выявили
настоящий беговой цикл `0035`: последовательные кадры показывают чередование ног
и рук. Reconstruction сохраняет позу `time=0`, а runtime отклоняет кандидат на
run, если заметное движение есть менее чем в 20 из 58 tracks.

Player snapshot публикует фактическую, в том числе ограниченную collision,
горизонтальную скорость, последнее направление, независимые таймеры idle/run и
плавный blend длительностью 0,12 с. Run phase следует скорости капсулы, Metal
смешивает локальные joint transforms до построения palette и поворачивает модель
по вектору движения.

Native regressions проверяют полный `idle→run→idle`, reconstruction начальных
keyframes, отказ на статическом/turn-only clip, принятие многосуставного цикла и
непрерывность representative skinned vertex. Debug-приложение проверено на
локальном Gaul ASTPAK: HUD переходит в `run`, а `0035` воспроизводит полный
58-bone беговой цикл при непрерывно зажатом движении. Прошли 35 native XCTest,
`make check` (56 Flutter-тестов), macOS debug build, diff review и resource
policy; локальный ASTPAK и screenshots не добавлялись в Git.

## П. 58 — Управляемая высота прыжка

**Выполнено:** 22 июля 2026.

Player runtime получил настраиваемое окно управления прыжком длительностью
0,2 с и дополнительное плавное замедление 28 м/с² после раннего отпускания
кнопки. Отпускание не меняет позицию и не обнуляет вертикальную скорость, а
последовательно сокращает оставшуюся восходящую фазу. После истечения окна
траектория сохраняет полную высоту независимо от момента отпускания. Одинаковая
логика заново запускается для разрешённого воздушного прыжка и сбрасывается при
приземлении, respawn и restore.

Fixed-tick regression-тесты сравнивают короткое нажатие, удержание ровно до
лимита и длительное удержание, повторяют короткую траекторию для проверки
детерминированности и подтверждают одинаковые минимальную/максимальную высоты
для наземного и воздушного импульсов. Отдельный тест фиксирует непрерывное
снижение восходящей скорости после отпускания. Прошли 31 native XCTest,
`make check` (56 Flutter-тестов), macOS debug build, diff review и resource
policy; игровые ресурсы не добавлялись.

## П. 57 — Двойной прыжок

**Выполнено:** 22 июля 2026.

Player runtime теперь принимает второе отдельное нажатие прыжка в воздухе и
задаёт капсуле ровно один дополнительный вертикальный импульс. Следующие
нажатия до посадки не меняют вертикальную скорость; право на воздушный прыжок
восстанавливается только после того, как capsule controller подтвердил
`grounded`. После respawn и restore оно остаётся недоступным до такого
подтверждения.

Native regression-тест воспроизводит полный цикл: наземный прыжок, переход
`jump → fall`, воздушный импульс с возвратом в `jump` и сбросом animation timer,
запрет третьего прыжка, подтверждённое приземление и новый двойной прыжок.
Прошли 29 native XCTest, `make check` (56 Flutter-тестов), macOS debug build,
diff review и resource policy; игровые ресурсы не добавлялись.

## П. 54 — Иконка исходного приложения для macOS

**Выполнено:** 22 июля 2026.

После явного подтверждения прав на использование и распространение исходная
32×32 `asterix.ico` из установленного приложения преобразована в полный набор
PNG 16, 32, 64, 128, 256, 512 и 1024 px. При масштабировании сохранены резкие
границы исходной пиксельной графики; все десять macOS 1×/2× slots продолжают
разрешаться существующим `AppIcon.appiconset/Contents.json`.

Release-сборка создала `asterix_xxl.app` с `CFBundleIconFile` и
`CFBundleIconName`, указывающими на `AppIcon`. В bundle присутствует
скомпилированный `AppIcon.icns`, а `Assets.car` содержит icon renditions во всех
заявленных размерах. Прошли `make check` (56 Flutter-тестов), macOS release
build, проверка asset catalog, diff review и resource policy. В Git добавлен
только явно разрешённый производный icon set; Windows executable и исходный
ICO остались вне репозитория.

## П. 56 — Движение Астерикса с клавиатуры

**Выполнено:** 22 июля 2026.

Стрелки влево/вправо и вперёд/назад добавлены как постоянные альтернативы
переназначаемым клавишам движения. Flutter router сохраняет независимое состояние
каждой нажатой клавиши, корректно обрабатывает key-down/key-up и публикует
нейтральный snapshot при потере активности приложения, исключая залипание
движения после переключения окна.

Native bridge преобразует action snapshot в ограниченные оси `move_x/move_z` и
теперь применяет последний snapshot даже тогда, когда он поступил до создания
Metal viewport. AppKit local monitor страхует ввод, когда встроенный `MTKView`
получает клавиатурные события вместо Flutter focus, и возвращает их в тот же
Flutter router; при деактивации окна он явно отпускает все направления.
Regression-тесты покрывают macOS key codes, четыре стрелки, одновременную
альтернативную клавишу, native axis mapping, движение капсулы по диагонали на
fixed ticks и полную остановку после отпускания.

Прошли `make check` (56 Flutter-тестов), 28 native XCTest, 9 Runner XCTest,
macOS debug build, diff review и resource policy; игровые ресурсы не добавлялись.

## П. 55 — Стартовая позиция Астерикса на земле

**Выполнено:** 22 июля 2026.

Инициализация Gaul теперь создаёт состояние капсулы через реальный ground probe,
а не через жёстко заданное вертикальное смещение. Нижняя точка капсулы
вычисляется из её `half_height` и `radius`, точно совмещается с выбранной
проходимой поверхностью, а стартовое состояние сразу сохраняет `grounded` и
`ground_object_id`. Точка checkpoint получает ту же скорректированную позицию.

Regression XCTest проверяет наклонную поверхность, совпадение нижней точки
капсулы с высотой земли с допуском `0.0001`, корректный ID опоры и отсутствие
проваливания или вертикального сдвига после первого fixed simulation tick.
Прошли 27 native XCTest, macOS debug build, diff review и resource policy;
оригинальные и производные игровые ресурсы в Git не добавлены.

## П. 53 — Visual regression запуска Gaul

**Выполнено:** 22 июля 2026.

Добавлен PNG comparator стартового gameplay-кадра Gaul и команда
`make visual-regression REFERENCE=... ACTUAL=...`. Сверка требует одинаковые
16:9 кадры не меньше 1280×720, отклоняет пустой render и контролирует среднюю
RGB-ошибку, долю изменённых пикселей всей сцены и более строгую центральную
область персонажа. Последний порог нужен, чтобы небольшой относительно кадра
T-pose или сдвиг spawn не потерялся в глобальной метрике.

Два локальных Retina-кадра 2560×1440 после отдельных холодных запусков дали
0,035% средней RGB-ошибки, 0,106% изменённых пикселей сцены и 1,106% в области
персонажа при лимитах 3,5%, 12% и 2,5% соответственно. Кадр одновременно
фиксирует стартовую камеру, окружение, texture bindings, idle-позу Астерикса и
HUD-состояние spawn/checkpoint/FOV. Эталон, actual PNG и Gaul ASTPAK хранятся
локально вне Git.

Синтетические тесты проверяют совпадение, крупное изменение pose/material и
защиту от пустого эталона. Прошли `make check` (53 Flutter-теста), 26 native
XCTest, macOS debug build, diff review и resource policy. Протокол и пороги
зафиксированы в [отчёте regression](../gameplay/gaul_launch_visual_regression.md).

## П. 52 — Fidelity материалов и геометрии Gaul

**Выполнено:** 22 июля 2026.

RenderWare triangle material IDs теперь разрешаются через material slots, в том
числе повторно используемые. Metal runtime нормализует texture lookup по имени,
пути, расширению и регистру, создаёт sampler по filtering/mipmap/U/V addressing
и классифицирует alpha textures как opaque, binary cutout либо blended. Cutout
использует alpha test, blended ranges рисуются отдельным проходом без записи
глубины.

Добавлена команда `asset_package.dart audit-materials`. На пересобранном
локальном Gaul ASTPAK она проверила 663 mesh, 149 038 triangles, 663 material
records и 293 уникальных texture names: неверных indices и потерянных texture
bindings нет; классифицированы 89 cutout и 33 blended textures. Solid/wireframe
smoke-сверка с локальной эталонной записью подтвердила terrain, окружение,
растительность и animated mesh Астерикса без marker fallback. Детали зафиксированы
в [отчёте fidelity](../gameplay/gaul_material_fidelity.md); точная камера/spawn и
автоматическое сравнение кадра остаются в п. 53.

Прошли importer regression, native XCTest, macOS debug build и resource policy;
оригинальные и производные игровые ресурсы в Git не добавлены.

## П. 51 — Skeletal animation Астерикса

**Выполнено:** 22 июля 2026.

Реальные LVL01 clips сопоставлены состояниям `idle/run/jump/fall/attack/hurt/death`.
Metal loader восстанавливает 58 animation tracks из RenderWare previous-frame
chains, строит hierarchy по HAnim push/pop flags, читает четыре joint indices и
weights каждого vertex и полные inverse bind matrices skin object 4.

На каждом render frame состояние и `state_seconds` player runtime выбирают и
sample-ят нужный clip. C++ runtime вычисляет полную 58-bone palette, renderer
добавляет gameplay-position и передаёт palette только draw-вызову Астерикса;
статическая сцена продолжает использовать identity bone. Idle/run loop-ятся,
one-shot состояния фиксируются на финальной позе до перехода state machine.

Review отделил player palette от static geometry, нормализовал служебные
flags/padding lanes RenderWare inverse-bind matrices и закрыл GPU out-of-bounds:
неполные clips, несовместимая hierarchy, невалидные joint indices/weights или
inverse binds приводят к безопасному marker, а не T-pose или повреждённому mesh.
Новый XCTest проверяет восстановление interleaved tracks, HAnim hierarchy и
полную palette. Прошли `make check` (49 Flutter tests), 26 native XCTest,
macOS debug build, diff review и resource policy; приложение smoke-запущено с
локальным ASTPAK. Оригинальные и производные игровые ресурсы в Git не добавлены.

## П. 42 — Приёмка vertical slice

**Выполнено:** 21 июля 2026.

Asset pipeline расширен с одного `STR01_00` до всех непустых секторов Gaul
Stage 1 (`STR01_00`–`STR01_03`). Manifest proof schema v2 сохраняет source и
directory каждого сектора, поэтому sector-local object IDs не конфликтуют.
Реальный локальный ASTPAK содержит 663 mesh, 131 texture, четыре collision
payload с 9 423 triangles, 345 animations, 38 skins и WAV; пакет и исходные
ресурсы остались вне Git.

Metal runtime использует настоящие section IDs и bounds для streaming, выбирает
старт только из collision `STR01_00`, показывает читаемые fallback materials и
видимые player/enemy markers. Живой прогон подтвердил около 60 FPS, движение,
бой, checkpoint 13 и schema-v2 autosave. Native regressions подтверждают
death/restart, combat, checkpoint rollback и audio events; Flutter tests —
save/load и presentation flow.

Пройдены `make check` (48 Flutter tests), 25 AsterixEngine XCTest, 7 Runner
XCTest, macOS debug build, diff review и resource policy. Результаты, hash
локального пакета, сравнение с эталоном и ограничения fidelity зафиксированы в
[отчёте приёмки](../gameplay/vertical_slice_acceptance.md). Character models,
per-material texture batches и полная gameplay orchestration переданы в оценку
п. 43 и content cycle п. 44.

## П. 41 — Presentation MVP

**Выполнено:** 21 июля 2026.

Добавлен launch screen и адаптивное главное меню с редактируемым активным
профилем. Continue включается только при валидном save; New Game начинает чистое
состояние выбранного профиля и не восстанавливает чужой checkpoint. Settings,
controls, HUD и pause overlay входят в единый presentation flow.

Fullscreen setting подключён к `NSWindow.toggleFullScreen` через method channel
и применяется сразу. Меню перестраивается в прокручиваемую compact-компоновку,
а developer panel скрывается на узком gameplay viewport. Tests подтверждают
отсутствие overflow на 560×420 и 1440×900; native Retina resize остаётся покрыт
Runner XCTest.

Добавлены русская и английская locale с Material/Cupertino delegates,
сохранением выбора и локализованными menu/settings/controls/HUD/pause строками.
Настройка субтитров управляет локализованным opening subtitle с безопасным
lifecycle timer. Контракт описан в
[документе presentation MVP](../architecture/presentation_mvp.md).

Review исправил восстановление save другого профиля при New Game и lifecycle
TextEditingController/timer. Прошли `make check` (47 Flutter tests), 7 Runner
XCTest, macOS debug build, diff review и resource policy; игровые ресурсы не
добавлялись.

## П. 40 — Аудио vertical slice

**Выполнено:** 21 июля 2026.

Добавлен fixed-tick `audio::Runtime` с независимыми music/effects volumes,
music/ambience beds, восемью каналами эффектов и priority preemption. Шаги,
атаки, попадания, действия врага, рычаг, награда, checkpoint и смерть связаны с
authoritative combat/enemy/interactive событиями и фазой run-анимации.

macOS playback построен на AVAudioEngine. Импортированный PCM16 WAV читается
напрямую из локального ASTPAK и зацикливается как фон; spatial effects проходят
через AVAudioEnvironmentNode с HRTF, а listener следует gameplay-камере.
Pause и application lifecycle приостанавливают audio graph вместе с renderer.

Flutter применяет сохранённые уровни музыки и эффектов при входе в gameplay и
после возврата из pause settings. Native stats сообщают готовность audio payload
и число активных эффектов. Контракт и ограничения описаны в
[документе audio runtime](../architecture/vertical_slice_audio.md).

Unit tests покрывают routing, idempotent loop beds, clamp громкости, priorities,
вытеснение и expiry каналов. Прошли `make check` (45 Flutter tests), 24 native
XCTest, macOS debug build, diff review и resource policy;
оригинальные или производные игровые ресурсы не добавлялись.

## П. 39 — Версионируемые сохранения

**Выполнено:** 21 июля 2026.

Добавлен JSON envelope schema v2 с profile ID/name, checkpoint ID, UTC timestamp
и authoritative gameplay payload. `SaveGameStore` сохраняет его в
`SharedPreferences`, закрыто обрабатывает повреждённые данные и неизвестные
версии. Реализована миграция legacy schema v1 с плоскими profile/checkpoint полями.

Native capture/restore включает position, checkpoint и health игрока; position и
health противника; reward counter, active checkpoint, triggers, levers,
destructible health и reward flags. Restore валидирует структуру и диапазоны,
синхронизирует combat fighters и устанавливает восстановленный мир как новый
baseline death/fall rollback.

Autosave выполняется при активации checkpoint и открытии паузы. При перезапуске
Flutter загружает профиль и отправляет state через method channel; Swift bridge
очередит restore до завершения асинхронной загрузки ASTPAK. Контракт и стратегия
миграций описаны в [документе versioned saves](../architecture/versioned_saves.md).

Тесты покрывают round-trip после пересоздания store, v1→v2 migration, corrupt и
future-schema rejection, native persistent world validation и новый checkpoint
baseline. Прошли 45 Flutter tests, analyze, 22 native XCTest, macOS debug build,
diff review и resource policy. Ресурсы не добавлялись.

## П. 38 — HUD, пауза и игровые настройки

**Выполнено:** 21 июля 2026.

Gameplay HUD переведён со статических значений на пакетный native snapshot:
показывает текущее/максимальное здоровье, progress bar, число наград и
локализованную контекстную подсказку для рычага, награды или respawn. Snapshot
поступает одним event stream с частотой 4 Hz, без frame-by-frame вызовов Flutter
к gameplay-объектам; диагностические performance counters используют тот же пакет.

Pause action теперь останавливает и возобновляет сам Metal renderer через
method-channel, а не только рисует overlay. Resume сбрасывает simulation-time
baseline и не создаёт catch-up ticks. Из pause menu доступны продолжение,
настройки и выход в меню.

Настройки музыки/эффектов сохраняются в `SharedPreferences`; чтение и запись
защищены clamp 0–100%. Экран управления сохраняет переназначения клавиатуры и
gamepad, включая `interact` на B/Circle. Применение уровней к mixer оставлено
задаче 40, fullscreen — задаче 41. Контракт описан в
[документе HUD/pause/settings](../architecture/hud_pause_settings.md).

Widget test проверяет передачу pause/resume в native channel, unit test —
persistence и валидацию громкости. Прошли 42 Flutter tests, analyze, 21 native
XCTest, macOS debug build, diff review и resource policy. Ресурсы не добавлялись.

## П. 37 — Интерактивы вертикального среза

**Выполнено:** 21 июля 2026.

Добавлен fixed-tick `interactive::Runtime` для AABB-триггеров, рычагов,
разрушаемых объектов, связанных наград и checkpoint. Состояние адресуется
устойчивыми ID и публикует события входа, взаимодействия, урона, разрушения,
подбора награды, активации и восстановления checkpoint.

В unified input snapshot добавлен action `interact`: клавиша `E` и gamepad B.
Рычаг реагирует только на фронт action в радиусе, destructible получает damage
из общей combat hitbox, а связанная награда становится доступна после разрушения.
Счётчик наград, checkpoint и состояния объектов опубликованы в native stats и
диагностическом Flutter HUD.

Checkpoint сохраняет mutable world snapshot. Падение синхронно откатывает мир с
capsule recovery; после смерти `interact` восстанавливает игрока с полным
здоровьем. Rollback возвращает триггеры, рычаг, destructible, награды, противника,
его combat-health и отменяет незавершённую атаку. Контракт описан в
[документе interactive runtime](../architecture/interactive_runtime.md).

XCTest покрывает one-shot trigger, lever edge, damage/destruction, появление и
подбор награды, а также checkpoint rollback и player respawn. Прошли `make check`,
21 native XCTest, macOS debug build, diff review и resource policy. Использован
только синтетический runtime-набор; оригинальные или производные ресурсы не
добавлялись.

## П. 36 — Навигация и первый противник

**Выполнено:** 21 июля 2026.

Добавлен отдельный fixed-tick `enemy::Runtime` со состояниями idle, pursuit,
attack, stun, death и returning. Конфигурируются perception и attack ranges,
скорость, leash, attack impact/duration/cooldown, stun, здоровье и урон. Противник
преследует живого игрока по collision surface, атакует один раз за цикл и после
потери цели или выхода за leash возвращается к spawn.

Runtime подключён к общей боевой системе как fighter другой команды. Player
combo наносит противнику damage и knockback, а enemy attack вызывает hurt/death
игрока. После смерти игрок не может начать новый удар. Второй capsule controller
не обновляет dynamic world повторно, поэтому геометрия продолжает двигаться ровно
один раз за simulation tick.

Metal loader выбирает spawn противника среди соседних допустимых ground points.
Native snapshot и Flutter diagnostic HUD показывают enemy state, health и
position. Контракт и ограничения описаны в
[документе enemy runtime](../architecture/enemy_runtime.md); оригинальные или
производные игровые ресурсы не добавлялись.

XCTest покрывает perception, pursuit, attack, проигрыш игрока, stun, knockback,
death, возврат в leash и победу игрока полной трёхударной комбинацией. Прошли
native XCTest, все Flutter tests, diff review и resource policy.

## П. 35 — Боевая система и первая комбинация

**Выполнено:** 21 июля 2026.

Добавлен data-driven fixed-tick `combat::Runtime`. Fighter содержит team,
transform/facing, AABB hurtbox, health, i-frame timer и knockback velocity;
attack stages задают duration, hit/input windows, локальный hitbox, damage и
knockback. Self/team/dead targets исключаются, а один stage не может нанести
одной цели повторный урон.

Первая комбинация содержит три удара с damage 1/1/2. Каждый stage длится 0,55 с,
следующий ставится в очередь только внутри input window; после одиночного или
финального удара действует recovery 0,10 с. Таким образом базовая длительность
0,55 с и повтор через 0,65 с совпадают с эталонными измерениями. Размеры hitbox и
окна поздних stages оставлены конфигурируемыми, поскольку из оригинала они не
извлечены.

Hit включает 0,4 с invulnerability, применяет направленный knockback и публикует
events attack-started/combo-queued/hit/defeated. Metal runtime связывает combat с
player transform, сохранённым facing и attack input; новый combo stage
перезапускает attack animation state. HUD snapshot показывает stage и hit window.

Unit-тесты покрывают input window, единственное попадание за stage, damage,
knockback, i-frames, сохранение facing и полную трёхударную комбинацию. Прошли
`make check`, native XCTest, Runner XCTest, diff review и resource policy.
Контракт и границы эталонных данных описаны в
[документе combat runtime](../architecture/combat_runtime.md).

## П. 34 — Gameplay-камера

**Выполнено:** 21 июля 2026.

Добавлен fixed-tick C++ `camera::Runtime`, следующий за authoritative player
position. Target dead zones удерживают персонажа в управляемой области кадра без
мелкой дрожи, а конфигурируемые AABB camera zones переопределяют дистанцию,
высоту, FOV, размеры зон и smoothing. Default FOV 70° и дистанция 10 world units
взяты из эталонных параметров; неподтверждённый специальный FOV 120° не принят
как gameplay default.

Collision avoidance проверяет segment target → camera против collision world,
выбирает ближайшую поверхность и применяет padding/near distance после
smoothing. Поэтому камера не интерполируется сквозь стену и сохраняет устойчивый
look-at даже в тесном пространстве.

Metal renderer использует camera snapshot для view/projection, frustum culling и
LOD distance; HUD публикует текущий FOV и collision-limited flag. Unit-тесты
покрывают dead zones, длительное слежение без потери игрока, zone override и
препятствие между target и камерой.

Прошли `make check`, native XCTest, Runner XCTest, diff review и resource policy.
Контракт и ограничения mapping оригинальных camera objects описаны в
[документе gameplay-камеры](../architecture/gameplay_camera.md).

## П. 33 — State machine Астерикса

**Выполнено:** 21 июля 2026.

Добавлен authoritative C++ `player::Runtime`, обновляемый только fixed simulation
tick. Он реализует `idle`, `run`, `jump`, `fall`, `attack`, `hurt` и терминальный
`death`, использует action snapshot задачи 32 и существующий capsule controller.
Grounded/vertical velocity определяют воздушные переходы и landing, диагональное
движение нормализуется, скорость плавно разгоняется и тормозит.

Attack и jump запускаются по фронту кнопки. Damage API учитывает health,
настраиваемые hurt/invulnerability windows и блокирует повторный урон; нулевое
health фиксирует death и запрещает дальнейшие переходы. Имена состояний являются
ключами animation clip; hitbox, combo windows и enemy damage source оставлены
за задачей 35.

Metal runtime строит collision world из ASTPAK, создаёт player runtime, принимает
пакетный input и публикует state/health/position в HUD snapshot. До импорта
подтверждённого spawn используется первый walkable collision triangle; замена на
checkpoint/spawn закреплена за задачей 37.

Unit-тесты покрывают idle → run → jump → fall → landing, one-shot attack,
hurt, invulnerability и death lock. Прошли `make check`, native XCTest, Runner
XCTest, diff review и resource policy. Контракт и параметры описаны в
[документе state machine](../architecture/asterix_state_machine.md).

## П. 32 — Единый ввод, remapping и переподключение

**Выполнено:** 21 июля 2026.

Добавлен единый Dart `GameInputRouter` для gameplay и pause UI. Он сводит
клавиатуру и нормализованные controller axes/buttons в actions движения, прыжка,
атаки и паузы; pause обрабатывается по фронту нажатия. Каждый изменившийся
snapshot пакетно передаётся native runtime, без покадровых object calls.

macOS-слой использует системный `GameController.framework` и extended gamepad
profile, общий для совместимых Xbox- и PlayStation-контроллеров. Connect и
disconnect публикуются во Flutter: отключение сразу очищает значения, а повторное
подключение заново устанавливает handlers. Текущий тип устройства виден в
gameplay.

Экран управления позволяет переназначать клавиши и controller controls,
сбрасывать раскладку и сохраняет версионированную конфигурацию в
`SharedPreferences`. Unit-тесты покрывают общий snapshot, pause edge, hot-plug и
сериализацию; widget-тест проверяет pause с клавиатуры. Прошли `make check`,
Runner XCTest, native XCTest, diff review и resource policy. Контракт описан в
[документе игрового ввода](../architecture/game_input.md).

## П. 31 — Debug tooling базового 3D-движка

**Выполнено:** 21 июля 2026.

Добавлена Flutter debug-панель и MethodChannel, передающий комбинируемую bit mask
без пересборки приложения или пересоздания `MTKView`. Metal renderer поддерживает
wireframe, красный world-space collision overlay с depth bias и стабильную
hash-раскраску mesh по импортированным object IDs. Collision buffer строится из
typed ASTPAK payload и учитывает transforms dynamic ground/wall.

Режимы triggers и navmesh доступны в той же панели и явно показывают нулевое
число элементов: соответствующие сериализованные данные в XXL1 Gaul не
подтверждены, поэтому debug tooling не создаёт фиктивную геометрию. Native
renderer маскирует неизвестные flags.

HUD продолжает получать одним snapshot четыре раза в секунду FPS, CPU/GPU frame
time, Metal memory, frame count, meshes, batches и resident sections; добавлены
collision triangle count и текущая debug mask. Runner XCTest также выявил и
исправил скрытую ошибку runtime-компиляции normal matrix в Metal shader;
диагностика shader/pipeline теперь сохраняется в `sceneError`.

Прошли `make check`, native XCTest, Runner XCTest, macOS debug build, widget
tests, diff review и resource policy. Контракт режимов описан в
[документе debug tooling](../architecture/debug_tooling.md). Пункт 31 завершает
веху M3.

## П. 30 — Коллизии мира и движение капсулы

**Выполнено:** 21 июля 2026.

Importer proof теперь извлекает `CGround`, `CDynamicGround` и `CWall` в
`collision.json`, а asset pipeline валидирует finite vertices и triangle ranges
и упаковывает данные в typed collision payload ASTPAK. Диагностический SVG не
попадает в пакет или Git.

Добавлен независимый C++20 capsule controller для fixed timestep: gravity и
ground probe, ограничение slope, подъём на ступени, итеративное разрешение стен,
subdivision быстрого перемещения против tunnelling, dynamic-ground movement и
rider carry по stable object ID. Падение ниже настраиваемого `kill_y`
восстанавливает checkpoint и сбрасывает velocity.

Синтетический маршрут проходит пол, склон и ступень, не проваливается и
останавливается у стены. Отдельный regression проверяет десять обновлений
движущейся платформы и fall recovery. Прошли `make check`, native XCTest, macOS
debug build, shell syntax/diff review и resource policy. Реализация и границы
проверки описаны в
[документе collision runtime](../architecture/world_collision_capsule.md).

## П. 29 — Фиксированный simulation timestep

**Выполнено:** 21 июля 2026.

Добавлен независимый C++20 `FixedTimestep` с шагом `1/60 s`. Accumulator
выполняет только целые simulation ticks, сохраняет остаток как interpolation
alpha и отдельно учитывает отброшенное время. Catch-up ограничен восемью ticks
на render frame, поэтому длительный stall не вызывает spiral of death;
отрицательный и non-finite elapsed отклоняются.

Metal proof больше не вычисляет animation state напрямую из wall clock. Fixed
ticks публикуют предыдущую и текущую фазу, а GPU palette получает
интерполированное render state. После resume monotonic timestamp начинается
заново, поэтому время sleep/suspend не симулируется задним числом.

Regression выполняет один десятисекундный сценарий при presentation 30, 60 и
120 Hz: во всех вариантах получены ровно 600 ticks, одинаковое authoritative и
интерполированное состояние. Отдельный тест покрывает half-step interpolation и
ограниченный catch-up. Прошли `make check`, native XCTest, macOS debug build,
diff review и resource policy. Контракт описан в
[документе fixed timestep](../architecture/fixed_simulation_timestep.md).

## П. 28 — Скелетная анимация и материалы

**Выполнено:** 21 июля 2026.

Добавлен независимый C++20 animation runtime: интерполяция translation и
shortest-path quaternion, sampling track, иерархическая joint palette с inverse
bind matrices и нормализованный four-weight skinning. Metal vertex stage
принимает joint indices/weights и palette; встроенная контрольная сцена
непрерывно проходит полный GPU skinning path, а статическая сцена использует
identity palette.

Material path теперь переносит normals, RGBA color, ambient/diffuse factors и
UV, использует mip filtering, directional Lambert lighting, alpha cutout,
source-alpha blending и линейный distance fog. Packed RenderWare alpha также
сохраняется. Исправлен контракт импортёра: skin JSON ранее терял render geometry,
теперь он содержит vertices, normals, UV, triangles и materials вместе с HAnim и
weights; старые локальные proof/ASTPAK требуют пересборки.

Native XCTest покрывает mid-clip pose, parent-child palette, skin result и fog.
Прошли `make check`, `make native-test`, macOS debug build, diff review и resource
policy. Архитектура и известное ограничение сортировки пересекающихся прозрачных
поверхностей описаны в
[отчёте](../architecture/skeletal_animation_materials.md); оригинальные и
производные игровые ресурсы в Git не добавлялись.

## П. 1 — Модель разработки и распространения ресурсов

**Выполнено:** 21 июля 2026.

Принята безопасная модель по умолчанию: публично распространяются новый движок, импортёр, документация форматов и синтетические фикстуры; оригинальные игровые данные извлекаются пользователем локально из законно приобретённой копии и не попадают в Git, CI или релизные артефакты.

Создана [политика разработки и распространения ресурсов](../legal/resource_distribution_policy.md), которая фиксирует:

- разрешённое содержимое репозитория;
- запрещённые оригинальные и производные материалы;
- требования к тестовым фикстурам;
- разделение репозитория и локальных игровых данных;
- правила исследования форматов;
- обязательный контроль и юридическую оценку перед публикацией.

**Принятое ограничение:** документ является инженерной политикой, а не юридическим заключением. До письменного разрешения правообладателей действует модель «движок и импортёр без оригинальных ресурсов».

## П. 2 — Защита репозитория от оригинальных данных

**Выполнено:** 21 июля 2026.

Добавлена многоуровневая защита:

- `.gitignore` блокирует оригинальные executable, библиотеки, `.KWN`, `.RWS`, сохранения, образы дисков и каталоги локальных данных;
- `scripts/check_resource_policy.sh` проверяет как текущие tracked-файлы, так и имена файлов во всей доступной Git-истории;
- `make policy-check` запускает проверку локально, а `make check` выполняет её перед форматированием, анализом и тестами;
- GitHub Actions запускает ту же проверку с полной историей на каждый push и pull request.

На момент выполнения запрещённых файлов в индексе и истории репозитория нет.

## П. 3 — Выбор вертикального среза

**Выполнено:** 21 июля 2026.

Для первой итерации выбран **Gaul — Stage 1 и ближайшая следующая штатная точка сохранения**: от получения управления Астериксом на стартовой тропе до первого save prompt после завершения этапа.

Решение и сравнительная матрица зафиксированы в [спецификации vertical slice](../gameplay/vertical_slice.md). Фрагмент занимает около 14,5 минуты по публичному прохождению и покрывает базовое движение, камеру, прыжки, бой, разрушаемые объекты, сбор, HUD и простые взаимодействия без уникальных систем поздних провинций.

**Допущение:** публичные данные относятся в том числе к консольным версиям. Точные границы, save prompt и состав обязательного маршрута должны быть подтверждены на оригинальной PC-версии в задаче 4. Связь с `.KWN`/`.RWS` будет установлена в задаче 7.

## П. 4 — Эталонное поведение vertical slice

**Выполнено:** 21 июля 2026.

На оригинальной русской PC-версии прямым прохождением подтверждены запуск и
главное меню, новая игра и повторная загрузка, базовое управление и камера, HUD,
бой, получение урона, смерть, восстановление с checkpoint, пауза и первая
штатная точка сохранения после Gaul Stage 1.

Наблюдения и их привязка к сценам зафиксированы в
[журнале эталонного поведения](../gameplay/reference_behavior.md). Основной
маршрут до обновления `AOXXL.sav` занял около 15 минут; изменение save
подтверждено временем модификации и SHA-256, а повторная загрузка не изменила
файл.

Вспомогательный локальный журнал содержит начало основного маршрута, паузу,
повтор checkpoint-маршрута, бой и измерительные манёвры с повторениями. Смерть,
загрузка и конечная save boundary подтверждены прямым наблюдением и метаданными,
но не представлены как покадровое видео. Для всех
принятых H.264-сегментов зафиксированы длительность, размер, разрешение и
SHA-256. Непрерывного видео всего основного маршрута нет, поэтому конечная
граница опирается на прямое наблюдение и метаданные save; это ограничение явно
сохранено для последующих измерений.

Оригинальные видео, контрольные кадры и `AOXXL.sav` остались вне Git. Review
подтвердил читаемость HUD и событий и пригодность боевых и измерительных
сегментов для задачи 5.

## П. 5 — Эталонные параметры

**Выполнено:** 21 июля 2026.

Создана [таблица эталонных параметров](../gameplay/reference_parameters.md) с
методом измерения, погрешностью и уровнем доверия для каждого значения. Точное
обрамление PC-версии — 640×480 (4:3), а локальный Retina-захват — 1280×960.

Из шести `CKCameraClassicTrack` исходного `LVL01.KWN` напрямую прочитаны FOV,
far distance, position/look-at и неизвестные параметры classic track. Пять
обычных камер используют FOV 70°, одна специальная — 120°; типичная базовая
дистанция camera-to-look-at равна 10 world units. Структура сопоставлена с
фиксированной revision первичного исходного кода XXL-Editor.

По исходным PTS измерительного журнала получены нормализованные параметры
движения и прыжка, тайминги атак и диапазоны реакции/неуязвимости. Пространство
нормализовано через высоту Астерикса `H`, поскольку world position игрока не
записывалась. Значения с низким доверием оставлены диапазонами и
конфигурируемыми стартовыми параметрами, а семантика неизвестных camera fields и
привязка конкретного `CKEnemyCpnt` отложены до каталога контента задачи 6.

Локальные видео, camera probe и извлечённые payload остаются вне Git.

## П. 6 — Каталог контента Gaul

**Выполнено:** 21 июля 2026.

Создан [каталог контента `LVL001`](../gameplay/content_catalog.md), построенный
прямым чтением inventory оригинальной PC-копии, protected-level probe,
sector geometry/textures/collision и class metadata. Каталог связывает level,
пять sectors, locale packs и 116 level-local RWS с исходными путями.

Для персонажей, противников, интерактивов и checkpoint приведены точные
`(category, classId)` и object counts: `CKGrpTrio`, 11 enemy squads, 18 basic
enemy hooks, 60 crate hooks, 90 bonus hooks, один checkpoint hook/group и
другие механизмы. Отдельно перечислены четыре `CKCinematicScene`, 14 scene data
и отсутствие standalone video containers.

Review отделяет сериализованные hooks/groups/components от фактического числа
spawn-объектов. Неподтверждённые личности NPC, обязательность механизмов,
назначение RWS и object-to-sector/event mapping явно оставлены неизвестными, а
не восстановлены по визуальному сходству. Оригинальные файлы и полные машинные
манифесты остаются вне Git.

## П. 7 — Карта файлов и контрольных состояний

**Выполнено:** 21 июля 2026.

Создана [карта файлов и состояний vertical slice](../gameplay/slice_file_state_map.md),
которая связывает запуск/menu, Gaul, sectors, audio/speech, cinematics,
checkpoint и persistent save с конкретными KWN/RWS/classes. Для шести основных
KWN приведены размеры и SHA-256; три `CKSas` описывают последовательные переходы
между четырьмя проходимыми sectors с точными AABB.

Вне Git сохранены baseline и after-Stage-1 snapshots `AOXXL.sav`. Оба имеют
размер 123 571 байт, но разные hashes; между ними 1 205 отличающихся байт в 74
диапазонах. After snapshot побайтно совпадает с live save после повторной
загрузки.

Состояния новой игры, диалога, урона, смерти, checkpoint restore, save boundary
и reload описаны до/после события. Runtime checkpoint явно отделён от
persistent save: фиктивные промежуточные `.sav` не создавались, а неизвестные
поля старого формата не интерпретировались. Оригинальные saves, KWN/RWS, видео и
дампы памяти остаются вне репозитория.

## П. 8 — Инвентаризация оригинальных файлов

**Выполнено:** 21 июля 2026.

Добавлен Dart CLI, который напрямую читает установленную локальную копию игры и создаёт детерминированный JSON-манифест с относительными путями, размерами, SHA-256, начальными сигнатурами, расширениями и номерами каталогов `LVLnnn`.

Инструмент и формат описаны в [спецификации инвентаризации](../formats/resource_inventory.md). Полный манифест хранится вне Git. Два последовательных запуска на локальной копии дали побайтно одинаковый результат: 837 файлов общим размером 966 449 733 байта.

Задача выполнена раньше задач 4–7, поскольку инвентаризация работает непосредственно с исходными `.KWN`/`.RWS` и не зависит от записи экрана. Видеозахват остаётся отдельным необязательным для импорта способом сверки поведения.

## П. 9 — Каркас импортёра и синтетическая фикстура

**Выполнено:** 21 июля 2026.

Созданы независимая от Flutter UI библиотека бинарного чтения и CLI импортёра. Чтение little-endian значений проверяет границы, а ошибки имеют устойчивый машинно-читаемый код, сообщение, путь, смещение и дополнительные детали.

Каркас проверяется на специально созданном контейнере `ASTX`, сохранённом в виде читаемой hex-фикстуры без данных оригинальной игры. Тесты покрывают успешный разбор, обрезанный файл, неверный размер, неподдерживаемую версию, отрицательную длину чтения и JSON-контракт ошибок. Формат и запуск описаны в [документе каркаса](../formats/importer_scaffold.md).

Каркас намеренно не приписывает оригинальному `.KWN` неподтверждённую структуру. Его реальные поля исследуются отдельно в задаче 10.

## П. 10 — Исследование структуры KWN

**Выполнено:** 21 июля 2026.

Исследованы все 108 KWN-файлов локальной PC-копии и выделены пять разных семейств: `GAME`, `GLOC`, `LLOC`, `LVL` и `STR`. Подтверждены little-endian encoding, отсутствие общей magic/version, абсолютные end-offsets без обязательного выравнивания, порядок категорий, объектные зависимости и отсутствие компрессионной обёртки в XXL1 PC.

Добавлен read-only structural probe для отдельных файлов и всего дерева. Он полностью валидирует envelopes `GAME`, `GLOC`, `LLOC` и `STR`; прогон прошли 99 таких файлов. Девять `LVL` распознаны как DRM-зависимый оригинальный PC layout и намеренно возвращают неполный статус до извлечения защищённого header/values.

Подтверждённая структура, результаты измерений, ссылки на первичный исходный код XXL-Editor и явно обозначенные неизвестные зафиксированы в [спецификации KWN](../formats/kwn.md). Тесты используют только созданные для проекта синтетические контейнеры.

## П. 11 — Извлечение геометрии и данных сцены

**Выполнено:** 21 июля 2026.

Реализовано прямое извлечение статических `CKGeometry` и sector-local scene nodes из `STRnn_mm.KWN`. Декодируются RenderWare frame hierarchy, матрицы, вершины, normals, UV sets, triangle indices, material IDs и object references `parent`/`next`/`child`/`geometry`. Все chunk boundaries и индексы проверяются со structured errors.

Пять sectors Gaul дали 663 mesh, 60 scene nodes, 131 469 вершин и 149 038 треугольников. Контрольный `STR01_00` экспортирован одной командой во внешний JSON: 381 mesh, 27 nodes, 49 852 вершины и 55 312 треугольников; автоматическая проверка подтвердила counts.

Реализация и ограничения описаны в [спецификации scene geometry](../formats/scene_geometry.md). Тесты используют синтетическую геометрию и отдельно проверяют vertices, indices, UV, frame hierarchy, node transform/references, выход индекса за границы и повреждённые chunks. Производные данные оригинальной игры остаются вне Git.

## П. 12 — Извлечение текстур и материалов

**Выполнено:** 21 июля 2026.

RenderWare material list теперь связывает triangle material IDs с цветом, коэффициентами освещения, sampler settings и texture names. Из sector `CTextureDictionary` напрямую извлекаются размеры, pitch, 4/8-bit palettes, pixels и alpha; RGBA PNG создаётся без внешнего конвертера или ручной правки.

Пять Gaul sectors содержат 131 texture entry с 85 уникальными именами. Контрольный `STR01_00` дал 52 валидных PNG; `tr_tromp_maiso_g01_p0` проверен как RGBA 64×64. В sector-файлах хранится только base mip, а флаг mipmaps переносится в manifest для последующей генерации pipeline.

Формат, material binding и ограничение защищённого общего level dictionary описаны в [спецификации текстур и материалов](../formats/textures_materials.md). Ссылки на отсутствующие в sector dictionaries level/global textures сохраняются по имени и явно помечаются внешними. Тесты проверяют material/texture binding, palette alpha, PNG signature и ошибки границ; оригинальные и производные ресурсы остаются вне Git.

## П. 13 — Извлечение скелета и анимации

**Выполнено:** 21 июля 2026.

Импортёр теперь находит открытую копию защищённого XXL1 level header в локальном `GameModule.elb`, валидирует все level object boundaries и читает ресурсы непосредственно из исходного `LVLnn.KWN`, не модифицируя файлы игры. Для Gaul подтверждены 3402 level objects и один `CAnimationManager`.

Из `LVL01` извлечены 345 RenderWare animations и 38 portable skins. Поддержаны float и compressed keyframes, duration, previous-frame links, HAnim hierarchy, vertex bone indices/weights и inverse bind matrices. Каждая анимация воспроизведена конвертером в трёх контрольных точках с получением local transform matrices; один legacy skin с non-finite float явно перечисляется как исключённый, а не маскируется.

Формат, алгоритм интерполяции, multi-costume ограничение и команда воспроизводимого экспорта описаны в [спецификации скелетной анимации](../formats/skeletal_animation.md). Unit-тест проверяет разбор и промежуточную позу синтетического clip, а неизвестная схема завершается structured error. Оригинальные и производные ресурсы остаются вне Git.

## П. 14 — Извлечение коллизий и пространственных данных

**Выполнено:** 21 июля 2026.

Реализовано прямое извлечение `CGround`, `CDynamicGround` и `CWall` из sector KWN: vertices, triangles, AABB, infinite/finite wall edges, surface parameters, scene-node IDs и transforms. Из защищённого level layout извлекаются `CKSas` с парами sector IDs и пространственных AABB.

Пять Gaul sectors дали 212 collision meshes, 7 395 вершин и 9 423 треугольника; `LVL01` содержит три области переходов между секторами 1–4. Для `STR01_00` автоматически создан SVG-overlay visual/collision geometry; визуальное ревью подтвердило совпадение collision surface с проходимой геометрией.

Формат и подтверждённое отсутствие более поздних `CKTrigger/CKTriggerDomain` в таблице классов XXL1 Gaul описаны в [спецификации коллизий](../formats/collision_spatial.md). Тесты проверяют успешный ground mesh и отклонение индекса вне vertex array. Производные данные оригинальной игры остаются вне Git.

## П. 15 — Исследование RWS и декодирование звука

**Выполнено:** 21 июля 2026.

Исследованы все 631 `.RWS` локальной PC-копии. Подтверждён RenderWare Audio
Stream с chunks `0x80D/0x80E/0x80F`, little-endian metadata и единственным codec
UUID Xbox IMA ADPCM. 545 локализованных speech banks используют mono 44.1 kHz,
86 level audio/music streams — stereo 48 kHz; все потоки имеют 4 bit/sample.

Добавлены безопасный parser, инспекция отдельного файла и дерева, удаление
sector padding, Xbox ADPCM decoder и экспорт первого segment в PCM S16LE WAV.
Синтетические тесты проверяют metadata, PCM/WAV и повреждённую границу chunk.
Полный прогон прочитал 631/631 файлов; контрольный `WINAS8.rws` декодирован вне
Git в stereo 48 kHz WAV длительностью 6.990667 s.

В [спецификации RWS](../formats/rws.md) описаны layout, codec, sample rates,
channels, секторизация и назначение дорожек. Файлы `SPEECH/l/l_WINn.RWS`
сопоставлены локализованным `CKSekens`, а segments — его репликам. Во всех
исследованных файлах marker count равен нулю: встроенные loop points не
обнаружены, и границы сегментов не интерпретируются как циклы. Оригинальные и
декодированные звуки остаются вне репозитория.

## П. 16 — Единый importer proof

**Выполнено:** 21 июля 2026.

Добавлен воспроизводимый сценарий `scripts/extract_slice_proof.sh`, который
принимает корень установленной игры и новый output directory. Одним запуском он
непосредственно извлекает из Gaul Stage 1 scene geometry/materials/nodes в JSON,
textures в RGBA PNG, animations и portable skins в JSON, а level audio в PCM
S16LE WAV. Корневой versioned manifest связывает все результаты и исходные
относительные пути.

Чистый локальный прогон без hex-редактора и ручной правки создал пакет 51 MB:
381 mesh, 27 scene nodes, 52 PNG, 345 animations, 38 skins и stereo 48 kHz WAV.
JSON проверен `jq`, audio — `ffprobe`. Сценарий отклоняет отсутствующие inputs и
существующий output, не позволяя старым артефактам маскировать неполную сборку.

Контракт, команда и граница между proof и будущим runtime pipeline описаны в
[документе M1](../formats/importer_proof.md). Оригинальные и производные ресурсы
остались вне Git. Веха M1 завершена.

## П. 17 — Архитектура workspace и runtime

**Выполнено:** 21 июля 2026.

Принят [ADR-001](../architecture/adr-001-runtime-workspace.md), фиксирующий
односторонние границы Flutter UI/Dart orchestration, offline importer,
версионируемого C ABI, platform-neutral C++ runtime, Metal renderer и macOS
bridge. Определена целевая структура `engine/include`, `engine/src`,
`engine/metal`, `engine/macos` и native tests.

ADR явно назначает владельцев UI/simulation/CPU/GPU data, opaque engine handle,
stable object IDs и allocator boundaries. Зафиксированы serial fixed-step engine
thread, immutable double-buffered render snapshots, bounded command/event queues
и отсутствие per-object FFI calls.

Описан полный lifecycle от create/attach через resize, Retina, suspend/resume до
detach/destroy, включая идемпотентное освобождение после частичной ошибки и hot
restart. C ABI получает version/struct size, POD transport и status вместо
исключений. Последующие задачи 18–22 содержат проверяемые условия реализации
этого решения; архитектурные отступления требуют нового ADR.

## П. 18 — Структура нативного ядра и Xcode targets

**Выполнено:** 21 июля 2026.

Созданы каталоги `engine/include`, `engine/src`, `engine/metal`, `engine/macos`
и `engine/tests`. Platform-neutral каркас ядра собирается как статическая
C++20-библиотека `AsterixEngine`; публичный C header и минимальная функция
версии подтверждают корректность компиляции и линковки, не подменяя реализацию
versioned transport из задачи 21.

`Runner` явно зависит от `AsterixEngine` и линкует библиотеку. Для нативного
кода добавлены отдельный hostless XCTest target `AsterixEngineTests`, shared
Xcode scheme и команда `make native-test`. Native targets изолированы от
CocoaPods/Flutter linker flags, поэтому тесты запускаются без Flutter host и
plugin frameworks.

Проверки подтвердили C++20 Build action, прохождение native XCTest, чистую
Flutter release-сборку и universal static library с архитектурами `x86_64` и
`arm64`. Полный `make check` и resource policy также прошли; оригинальные или
производные игровые ресурсы не добавлялись.

## П. 19 — MTKView в Flutter-окне и Retina-resize

**Выполнено:** 21 июля 2026.

В `engine/macos` добавлены factory и subclass нативного `MTKView`. Factory
регистрируется через macOS Flutter registrar как `asterix/metal-viewport`, а
игровой экран создаёт соответствующий `AppKitView` вместо прежней заглушки.
Flutter HUD и pause overlay остаются верхними слоями `Stack`; для платформ без
AppKit сохранён безопасный Flutter fallback.

`MetalViewportView` пересчитывает `drawableSize` при изменении frame, появлении
в окне и смене backing properties. Размер переводится из logical points в
физические пиксели через актуальный `backingScaleFactor`, включая округление
дробных размеров вверх; автоматический resize MetalKit отключён, чтобы правило
было явным и тестируемым.

Runner XCTest проверяет создание именно Metal view, pixel format, 2× Retina и
дробный resize. Widget-тест подтверждает выбор `AppKitView` на macOS и наличие
Flutter HUD над viewport. Прошли Runner/native XCTest, полный `make check`,
resource policy и Flutter macOS release build. Оригинальные игровые ресурсы не
добавлялись.

## П. 20 — Lifecycle Metal renderer

**Выполнено:** 21 июля 2026.

В `engine/metal` добавлен Objective-C++ `AsterixMetalRenderer`, который владеет
Metal command queue, реализует `MTKViewDelegate` и явные состояния running,
suspended и stopped. Resize обновляет сохранённый drawable size; кадр очищает и
предъявляет drawable через command buffer, не передавая Metal-типы в C++ core.

AppKit bridge приостанавливает display callbacks при потере активности,
невидимом/свёрнутом окне и sleep, а после foreground/wake возобновляет их только
для видимого окна. При уничтожении platform view снимаются все observers,
renderer переводится в stopped, перестаёт принимать кадры, снимает delegate,
ожидает завершения in-flight command buffers и освобождает command queue.
Повторные suspend/resume/stop безопасны.

Runner XCTest покрывает переходы lifecycle, resize, повторный stop, снятие
delegate и 100 циклов create/stop/release с weak-проверкой освобождения.
Прошли Runner/native XCTest, Flutter release build, полный `make check` и
resource policy. Оригинальные или производные игровые ресурсы не добавлялись.

## П. 21 — Versioned C ABI и Dart FFI transport

**Выполнено:** 21 июля 2026.

Определён и реализован [C ABI v1](../architecture/c_abi_v1.md): opaque engine
handle, version/struct size, status codes, batch commands, компактный UI
snapshot и пакетная выгрузка events. Минимальные размеры v1 привязаны к
последним обязательным полям, поэтому добавление полей в конец не ломает старых
клиентов той же major ABI. Исключения C++ преобразуются в status.

Engine session запускает serial worker thread. Dart producer и simulation
consumer связаны bounded SPSC command ring; batch помещается целиком либо
возвращает queue full. Worker публикует authoritative UI state через два
snapshot buffers с атомарной сменой front index. Отдельный bounded event ring
не вызывает Dart callbacks; переполнение отражается счётчиком в snapshot.

Bindings генерируются ffigen из публичного header и не редактируются вручную.
Dart wrapper владеет handle, использует caller-allocated buffers, пакетные
enqueue/drain и `NativeFinalizer`. Runner экспортирует ABI symbols для
`DynamicLibrary.process()`.

Воспроизводимый integration-test собирает dylib из того же `engine.cpp` и
проверяет реальную цепочку Dart → C ABI → worker → double-buffer snapshot →
events, atomic queue full и наблюдаемое event overflow. Также прошли native
XCTest, Xcode static analysis, Runner XCTest, Flutter release build, полный
`make check` и resource policy; игровые ресурсы не добавлялись.

## П. 22 — Тестовая Metal-сцена и Flutter HUD

**Выполнено:** 21 июля 2026.

`AsterixMetalRenderer` теперь выводит вращающийся цветной треугольник через
перспективную камеру с FOV 70° и отдельным `Depth32Float` attachment. Aspect
ratio берётся из физического Retina drawable; pipeline, vertex buffer и depth
resources освобождаются вместе с renderer lifecycle.

Renderer публикует сглаженный FPS, CPU submission time, GPU execution time,
число кадров и Metal allocated memory. `MetalViewportFactory` отправляет
агрегированный snapshot в Flutter HUD четыре раза в секунду через EventChannel,
без покадровых Dart→native вызовов.

Profile-проверка на доступном M2 validation baseline (MacBook Pro, Apple M3 Max,
viewport 800×600 logical / 1600×1200 physical) дала стабильные 59,9–60,0 FPS;
контрольный snapshot — CPU 0,28 ms, GPU 0,06 ms и 64,8 MiB Metal allocation.
Методика и границы результата зафиксированы в
[документе M2](../architecture/metal_scene_proof.md).

Review выявил и устранил критическую ошибку инициализации: одноаргументный
унаследованный `MTKView.init(frame:)` оставлял `CAMetalLayer.device` пустым.
Фабрика теперь явно передаёт `MTLCreateSystemDefaultDevice()`, а Runner XCTest
проверяет device и готовность scene pipeline. Прошли `make check`, Runner XCTest,
profile host verification и resource policy; оригинальные игровые ресурсы не
добавлялись.

## П. 23 — Версионируемый runtime-формат ресурсов

**Выполнено:** 21 июля 2026.

В [ADR-002](../architecture/adr-002-runtime-asset-package.md) выбран собственный
контейнер ASTPAK вместо glTF-only решения. Importer proof содержит scene graph,
collision, spatial data, animations и audio за пределами базовой модели glTF;
при этом GLB при необходимости может храниться как typed payload внутри ASTPAK.

Реализованы детерминированные builder и reader ASTPAK 1.0: 48-байтовый
little-endian header, canonical JSON manifest, 16-byte-aligned payload ranges и
SHA-256 каждого ресурса. Reader проверяет версии, границы, canonical identity,
уникальность IDs, ссылки и checksums до выдачи immutable manifest/payload.
Добавлена команда `make package-inspect INPUT=...`.

Manifest 1.0 описан отдельной
[JSON Schema](../formats/schemas/asterix-runtime-manifest-v1.schema.json) и
[спецификацией binary layout](../formats/runtime_asset_package.md). Устойчивый ID
`astx:<kind>:<128-bit hex>` зависит от нормализованных `kind`, относительного
source path и source object key, но не от изменяемых payload bytes. Совпадения
ID, неканонические locators и неявное переназначение завершаются ошибкой.

Синтетические тесты покрывают побайтную детерминированность независимо от
порядка input, round trip двух payload, alignment, стабильность IDs при
изменении содержимого, отсутствующие/дублированные ссылки, global ID collision,
неподдерживаемую версию, corruption checksum и immutable parsed manifest.
Прошли `make check`, JSON syntax check и resource policy; оригинальные или
производные игровые ресурсы не добавлялись.

## П. 24 — Воспроизводимый asset pipeline

**Выполнено:** 21 июля 2026.

Добавлен однокомандный сценарий `scripts/build_slice_assets.sh GAME_ROOT
OUTPUT.astpak`: он создаёт временный importer proof и преобразует его в ASTPAK
1.0, не сохраняя исходные или производные игровые ресурсы в репозитории.
Pipeline упаковывает canonical JSON геометрии, scene graph, 345 анимаций,
38 скинов, WAV-аудио и scene manifest со стабильными ASTPAK IDs.

PNG-текстуры преобразуются в документированный контейнер `ASTMTEX` v1 с
Metal-совместимым `rgba8Unorm`, плотно упакованными пикселями и полной цепочкой
mipmaps до 1×1. Для воспроизводимости mipmaps строятся собственным 2×2 box
filter, а JSON сериализуется с рекурсивно отсортированными ключами.

Синтетический тест проверяет побайтово одинаковый результат при разном порядке
создания входов, состав ресурсов и layout двух mip levels. Полный Flutter test
suite и static analysis проходят. Два чистых запуска на доступной установке
игры извлекли 52 текстуры и создали одинаковые пакеты размером 34 956 780 байт с
SHA-256 `a6f3fd60f6d3264a038216224f2303e8998da29f34715156abbf7527756b32d1`.

## П. 25 — Валидация, кеш и инкрементальная сборка

**Выполнено:** 21 июля 2026.

Asset pipeline теперь до упаковки проверяет версии и обязательные поля
manifest, уникальность mesh/node IDs, raw/decoded object references, размеры
текстур, соответствие manifest файлам анимаций/скинов, RIFF/WAVE audio и
диапазоны vertex/material indices. Ошибки имеют стабильные `error`, `message`,
`path` и `details`; повреждённая mesh-фикстура завершается контролируемой
`invalidRange`, не создавая частичный ASTPAK.

Добавлен content-addressed кеш преобразований mesh, texture, animation, skin и
audio. Ключ включает версию pipeline, тип преобразования и SHA-256 входа, а
cache entry защищён собственной длиной и SHA-256. Повреждённый кеш не
используется и автоматически пересобирается. CLI сообщает rebuilt/cached
counts, поддерживает явные `--cache` и `--force`, а output сначала создаётся во
временном файле.

Синтетический тест подтвердил нулевую пересборку без изменений, ровно один
cache miss при изменении одной анимации и восстановление повреждённого cache
entry с побайтно прежним ASTPAK. Прошли полный `make check`, static analysis,
resource policy и весь Flutter test suite; оригинальные или производные игровые
ресурсы не добавлялись.

## П. 26 — Импортированная статическая сцена в Metal

**Выполнено:** 21 июля 2026.

Metal renderer загружает локальный ASTPAK 1.0, проверяет header/ranges и manifest,
создаёт Metal vertex buffer для всех mesh resources, применяет нормализованные
scene-node transforms и загружает уровни ASTMTEX в `rgba8Unorm` textures.
Существующие perspective camera, Retina aspect ratio и `Depth32Float` attachment
используются для полной импортированной сцены; камера автоматически кадрирует её
bounding volume.

Путь передаётся через `ASTERIX_ASSET_PACKAGE`; platform-view factory объявляет
StandardMessageCodec и сообщает в Flutter HUD число mesh либо контролируемую
ошибку. Profile-запуск с package автоматически открывает viewport, обычный
запуск сохраняет главное меню и безопасную proof-сцену.

На локальном пакете Gaul `STR01_00` отображены все 381 mesh. Силуэт, ориентация
и размещение сопоставлены с reference capture задачи 4 и visual/collision
overlay задачи 14. При viewport 800×600 logical / 1600×1200 physical получены
стабильные 60.0 FPS, CPU 0.07–0.10 ms, GPU 0.18 ms и 64.9 MiB Metal allocation.
Подробности и команда запуска зафиксированы в
[отчёте](../architecture/metal_static_scene.md). Расширенные material batches,
lighting, transparency, fog и effects оставлены задаче 28.

Review исправил отсутствующий creation-args codec, sandbox diagnostics, crash на
packed RenderWare color, legacy homogeneous slots affine matrix, недетерминированный
выбор ресурсов и загрузку только трёх mesh, имевших прямые scene-node references.
Прошли Flutter tests/analyze, native XCTest, macOS debug/profile build и resource
policy. ASTPAK, screenshots и исходные/производные игровые ресурсы остались вне Git.

## П. 27 — Scene graph и streaming секций

**Выполнено:** 21 июля 2026.

Добавлен независимый C++20 [scene runtime](../architecture/scene_graph_streaming.md),
который разрешает local-to-world иерархию transforms и контролируемо отклоняет
дублированные ID, отсутствующих родителей и циклы. Asset pipeline сохраняет в
metadata типизированные `parentId`, `childId`, `nextId` и section ID; Metal loader
использует вычисленные world transforms при подготовке статической геометрии.

Runtime управляет requested/resident состоянием нескольких секций через
расширенный preload-frustum и 120-кадровую задержку eviction. Загрузка ASTPAK и
подготовка Metal ресурсов вынесены с UI/render thread, а новый buffer, textures,
mesh ranges и граф публикуются одним синхронизированным swap. Render frame держит
собственную устойчивую resource generation до GPU submission.

Для каждого кадра mesh AABB проверяются против шести frustum planes, дальние
mesh получают первичный triangle-aligned LOD, а видимые draw items стабильно
группируются по material/LOD. Native HUD snapshot дополнен loaded/visible mesh,
batch и resident section counters.

XCTest покрывает композицию иерархии, циклы, request/eviction секций, culling,
batching и LOD. Moving-frustum regression с 381 синтетическим mesh прошла 600
кадров за 0,062 с и проверила каждый selection update против 16 ms frame budget.
Также прошли полный `make check`, native XCTest, macOS debug build, diff review и
resource policy. Локального ASTPAK для повторного profile-прогона не было;
оригинальные или производные игровые ресурсы в Git не добавлялись.
## П. 73 — Анимация движения воды

**Выполнено:** 22 июля 2026.

Исходный механизм определён как material UV transformation: RenderWare
Material Effects использует UV effect type 5, а `CKHkWaterFall` хранит отдельные
множители скорости по X/Y. Pipeline маркирует только шесть подтверждённых
водных материалов Gaul и сохраняет механизм, направление, скорость, нулевую
начальную фазу, repeat addressing и simulation clock в mesh payload.

Metal применяет UV offset, сохраняя исходные texture bindings, alpha, filtering
и addressing. Presentation simulation seconds входят в save state; pause не
двигает воду, restore возвращает фазу, а streaming residency её не перезапускает.
Pipeline regression исключает static fallback, native visual regression
подтверждает изменение фазы и детерминированность pause/restore/streaming.

Архитектурное описание: `documents/architecture/water_animation.md`. Прошли
`make check`, native XCTest, macOS debug build, diff review и resource policy;
оригинальные или производные игровые ресурсы в Git не добавлялись.

## П. 72 — Анимированный огонь на горящих домах

**Выполнено:** 22 июля 2026.

Asset pipeline извлекает particle FX-ноды горящих домов, сохраняет их world-позиции,
режимы, rate, texture bindings и section в отдельном `burning-house-fire`
payload. Отключённые authored-ноды не становятся видимыми эффектами, а
некорректные параметры отклоняются контролируемой ошибкой.

Metal runtime валидирует все fire bindings, создаёт camera-facing прозрачные
quads и воспроизводит flame/ember/smoke с детерминированной фазой от simulation
time. Эмиттеры публикуются вместе с package resources и переживают streaming и
pause без static fallback. Добавлены pipeline и scene-node regressions.
