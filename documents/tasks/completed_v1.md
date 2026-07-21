# Выполненные задачи первой итерации

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
