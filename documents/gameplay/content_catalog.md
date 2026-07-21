# Каталог контента Gaul (`LVL001`)

## Назначение и достоверность

Каталог построен прямым чтением локальной PC-копии: inventory всех файлов,
structural probe защищённого `LVL01.KWN`, импорт geometry/textures/collision из
`STR01_00`–`STR01_04` и class metadata XXL-Editor. Оригинальные файлы и полные
машинные манифесты хранятся вне Git.

Здесь различаются:

- **подтверждено файлом** — имя, размер, class ID или количество объектов
  прочитаны непосредственно;
- **подтверждено наблюдением** — сущность видна в эталонном прохождении;
- **гипотеза** — семантика class/object ещё не связана с конкретным spawn или
  событием.

Количество hooks, groups и components не следует считать числом видимых
экземпляров: один gameplay-объект может использовать несколько сериализованных
объектов, а pool/group может создавать экземпляры во время игры.

## Файловая область среза

`LVL001/` содержит 127 файлов общим размером 192 673 069 байт:

| Набор | Файлы | Размер / назначение | Статус |
|---|---:|---|---|
| `LVL001/LVL01.KWN` | 1 | 13 374 431 байт; 3 402 level objects, gameplay logic, cameras, animations, groups, hooks | Подтверждено файлом |
| `LVL001/STR01_00.KWN` … `STR01_04.KWN` | 5 | Sector-local geometry, scene nodes, textures, collision | Подтверждено файлом |
| `LVL001/00LLOC01.KWN` … `04LLOC01.KWN` | 5 | По 6 350 байт; пять locale object packs | Языковая семантика индексов не подтверждена |
| `LVL001/WINAS/WINAS0.rws` … `WINAS10.rws` | 11 | 51 705 856 байт; level-local non-speech audio banks | Назначение отдельных банков — задача 15 |
| `LVL001/WINAS/SPEECH/{0..4}/*_WIN*.RWS` | 105 | Пять наборов по 21 speech bank, всего 118 786 048 байт | Индексы реплик и языков требуют декодирования в задаче 15 |
| `GAME.KWN` | 1 global | Game/manager objects | Подтверждено структурным probe |
| `00GLOC.KWN` … `04GLOC.KWN` | 5 global | Global locale packs | Нужны для общей UI/locale-семантики, точная связь со срезом не доказана |

Все 631 аудиофайл установки имеют расширение `.RWS`; отдельных `.wav`, `.mp3`,
`.bik`, `.avi` или `.mpg` в inventory нет.

## Пространственные sectors

| Sector | Размер KWN | Mesh | Scene nodes | Вершины | Треугольники | Local textures | Collision meshes / vertices / triangles | Роль |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| `STR01_00` | 3 506 722 | 381 | 27 | 49 852 | 55 312 | 52 | 90 / 2 360 / 2 576 | Самый крупный стартовый/лесной набор; точная граница маршрута требует task 7 |
| `STR01_01` | 2 196 572 | 74 | 14 | 29 617 | 33 472 | 34 | 58 / 2 183 / 2 789 | Проходимый sector с crate/terrain references |
| `STR01_02` | 1 550 269 | 102 | 14 | 27 330 | 30 847 | 23 | 50 / 998 / 1 084 | Проходимый sector |
| `STR01_03` | 1 519 401 | 106 | 4 | 24 670 | 29 407 | 22 | 14 / 1 854 / 2 974 | Проходимый sector с road/river texture references |
| `STR01_04` | 2 020 | 0 | 1 | 0 | 0 | 0 | 0 / 0 / 0 | Служебный пустой sector; назначение не подтверждено |

Итого: 663 mesh, 60 scene nodes, 131 469 вершин, 149 038 треугольников,
131 texture entry (85 уникальных имён) и 212 collision meshes. `LVL01` также
содержит три `CKSas` spatial regions между sectors 1–4.

## Персонажи и NPC

| Class / объект | Count | Интерпретация | Достоверность |
|---|---:|---|---|
| `CKGrpTrio` (category 4, class 12) | 1 | Gameplay-группа Астерикса, Обеликса и Идефикса | Class подтверждён; состав подтверждён наблюдением |
| `CKHkAnimatedCharacter` (2/97) | 33 | Hooks анимированных персонажей для сцен/NPC | Class/count подтверждены; личности не сопоставлены |
| `CKHkClueMan` (2/161) | 8 | Персонажи-подсказчики; встреченный шпион относится к этому типу предположительно | Тип/count подтверждены, конкретный object ID — гипотеза |
| `CKHkWildBoar` (2/171) | 6 | Кабаны | Class/count подтверждены; участие в обязательном маршруте не подтверждено |
| `CKHkAsterixShop` (2/172) | 1 | Shop hook | Class/count подтверждены; доступность в Stage 1 не подтверждена |
| `CAnimationManager` | 1 | 345 animation clips и 38 portable skins (один non-finite skin исключён) | Подтверждено прямым импортом |

В прохождении непосредственно видны Астерикс, Обеликс, Идефикс, шпион и
персонажи вступительной/обучающих сцен. Имена остальных 33 animated-character
hooks нельзя выводить только из class ID.

## Противники и бой

| Class / объект | Count | Интерпретация | Достоверность |
|---|---:|---|---|
| `CKGrpSquadEnemy` (4/26) | 11 | Enemy squad groups | Подтверждено файлом |
| `CKHkBasicEnemy` (2/93) | 18 | Basic enemy hooks | Подтверждено файлом |
| `CKHkBasicEnemyLeader` (2/148) | 2 | Leader hooks | Подтверждено файлом |
| `CKBasicEnemyCpnt` (6/10) | 10 | Shared/basic enemy components | Подтверждено файлом; component count не равен spawn count |
| `CKHkSquareTurtle` (2/110) | 1 | Square-turtle/shield formation hook | Class/count подтверждены; обязательность не подтверждена |
| `CKSquareTurtleCpnt` (6/29) | 1 | Компонент той же formation | Подтверждено файлом |

Эталонное прохождение подтверждает обычных и щитоносных римских легионеров,
групповой бой, получение урона и смерть. Связь каждого hook с sector, squad и
конкретной моделью требует object-reference map; она не подменяется визуальным
предположением.

## Интерактивные объекты и бонусы

| Class / объект | Count | Назначение | Статус |
|---|---:|---|---|
| `CKHkCrate` (2/112) | 60 | Разрушаемые ящики/контейнеры | Class/count подтверждены; ящики видны в срезе |
| `CKHkBasicBonus` (2/114) | 90 | Базовые pickup/bonus hooks | Class/count подтверждены; тип каждого pickup не сопоставлен |
| `CKGrpAsterixBonusPool` (4/63) | 8 | Asterix bonus pools | Class/count подтверждены; тип bonus каждого pool не сопоставлен |
| `CKHkPowderKeg` (2/77) | 1 | Powder keg | Class/count подтверждены |
| `CKHkDrawbridge` (2/34) | 1 | Drawbridge | Class/count подтверждены; обязательность не доказана |
| `CKHkCorkscrew` (2/44) | 1 | Corkscrew mechanism | Class/count подтверждены |
| `CKHkActivator` (2/52) | 1 | Activator | Class/count подтверждены |
| `CKHkSlideDoor` (2/100) | 1 | Sliding door | Class/count подтверждены |
| `CKHkCrumblyZone` (2/102) | 2 | Разрушаемые зоны | Class/count подтверждены |
| `CKHkPushPullAsterix` (2/147) | 2 | Push/pull interactions | Class/count подтверждены |
| `CKHkLightPillar` (2/60) | 2 | Light-pillar hooks | Class/count подтверждены |
| `CKHkWaterFall` (2/185) | 2 | Waterfall hooks | Class/count подтверждены |
| `CKHkLight` (2/195) | 6 | Dynamic light hooks | Class/count подтверждены |

Дополнительно сериализованы torch, hearth и water/sky/interface hooks. Они
включаются в полный object-reference manifest, но не объявляются обязательными
gameplay-интерактивами без связи с событиями маршрута.

## Музыка, звуки, речь и ролики

| Категория | Файловое подтверждение | Семантический статус |
|---|---|---|
| Level audio / music / SFX | 11 `LVL001/WINAS/WINAS*.rws` | Содержимое, codec, sample rate, channels, loop points и назначение tracks исследуются в задаче 15 |
| Speech | 5 каталогов × 21 RWS | Пять параллельных наборов подтверждены; соответствие индекса языку и реплике не подтверждено |
| Cinematics | 4 `CKCinematicScene` и 14 `CKCinematicSceneData` в `LVL01.KWN` | Сцены исполняются движком; object/event mapping ещё не готов |
| Standalone video | 0 файлов известных video-расширений | Наблюдаемые вступления нельзя каталогизировать как отдельное видео; evidence указывает на engine-rendered sequences |

## Checkpoint и save boundary

В `LVL01.KWN` присутствуют ровно по одному:

- `CKHkAsterixCheckpoint` (category 2, class 193);
- `CKHkAsterixCheckpointLife` (3/124);
- `CKGrpAsterixCheckpoint` (4/75);
- `CKGrpAsterixCheckpointLife` (5/29).

`CKAsterixGameManager` содержит ссылку `dgmGrpCheckpoint`. Прямое прохождение
подтверждает восстановление после смерти и обновление `AOXXL.sav` на выбранной
границе, но привязка checkpoint object ID к sector/position и состояния
до/после события выполняется в задаче 7. Сам save остаётся вне Git.

## Источники class semantics

Названия classes и осторожная семантика сопоставлены с первичным кодом
XXL-Editor revision `d606cfc`:

- [`Properties_XXL1.json`](https://github.com/AdrienTD/XXL-Editor/blob/d606cfccf8faa31287aa1326fa9d10c292c06157/resources/Properties_XXL1.json);
- [`CKGameX1.h`](https://github.com/AdrienTD/XXL-Editor/blob/d606cfccf8faa31287aa1326fa9d10c292c06157/GameClasses/CKGameX1.h);
- [`CKHook.h`](https://github.com/AdrienTD/XXL-Editor/blob/d606cfccf8faa31287aa1326fa9d10c292c06157/CoreClasses/CKHook.h);
- [`CKGroup.h`](https://github.com/AdrienTD/XXL-Editor/blob/d606cfccf8faa31287aa1326fa9d10c292c06157/CoreClasses/CKGroup.h).

Имена используются только там, где `(category, classId)` совпали с исходным
`LVL01`; неизвестная семантика отмечена явно.
