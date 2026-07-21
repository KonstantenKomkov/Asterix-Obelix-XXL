# Формат KWN — Asterix & Obelix XXL 1 PC

## Область исследования

Документ описывает локальную PC-копию XXL1 и пять семейств из 108 файлов: `GAME` (1), `GLOC` (5), `LLOC` (45), `LVL` (9) и `STR` (48). Размеры — от 146 до 18 431 284 байт.

Проверка выполнена собственным structural probe и сопоставлена с исходным кодом [XXL-Editor, revision d606cfc](https://github.com/AdrienTD/XXL-Editor/tree/d606cfccf8faa31287aa1326fa9d10c292c06157). Главные первичные источники: [загрузка GAME/LVL/STR](https://github.com/AdrienTD/XXL-Editor/blob/d606cfccf8faa31287aa1326fa9d10c292c06157/KEnvironment.cpp) и [локальные пакеты GLOC/LLOC](https://github.com/AdrienTD/XXL-Editor/blob/d606cfccf8faa31287aa1326fa9d10c292c06157/KLocalObject.cpp).

## Общие свойства

- Порядок байтов little-endian.
- Общей сигнатуры и встроенного номера версии нет. Вариант формата задаётся игрой, платформой и семейством файла; поэтому первые `uint32` нельзя трактовать как magic/version.
- Смещения `next/end` абсолютны от начала файла и указывают на первый байт после блока.
- Глобального выравнивания нет: валидные блоки заканчиваются и на нечётных смещениях.
- Исследованные PC XXL1-файлы не имеют gzip/zlib-обёртки. В XXL-Editor gzip включается только для более поздних версий движка.
- Payload объектов зависит от пары `(category, classId)` и содержит ссылки на глобальные, level и sector objects. Его разбор требует таблицы классов и контекста загрузки.

## `GAME.KWN`

```text
u32 objectCount
u32 gameManagerId
repeat objectCount:
  u32 category
  u32 classId
  u32 endOffset
  u8  payload[endOffset - currentOffset]
```

В локальной копии: четыре объекта, `gameManagerId = 51`; цепочка end-offset заканчивается ровно на размере файла. `GAME` должен загружаться до level/sector, поскольку их payload может ссылаться на глобальные экземпляры.

## `nnGLOC.KWN` и `LVLnnn/nnLLOCnn.KWN`

```text
u32 objectCount
repeat objectCount:
  u32 category
  u32 classId
  u32 endOffset
  u8  payload[endOffset - currentOffset]
```

Все `GLOC` содержат по четыре объекта, все `LLOC` — по шесть. `GLOC` хранит глобальную локализацию и 2D-ресурсы, `LLOC` — локализованные level-ресурсы. Все 50 файлов имеют монотонные offsets и заканчиваются на последнем `endOffset`.

## `STRnn_mm.KWN`

Sector-файл состоит из directory и object payload envelope.

```text
for category 0..14:
  u16 classCount
  repeat classCount:
    u16 instanceCount

for category in [0,9,1,2,3,4,5,6,7,8,10,11,12,13,14]:
  u16 activeClassCount
  u32 categoryEndOffset
  for each class where instanceCount > 0:
    u32 classEndOffset
    u16 absoluteStartObjectId
    repeat instanceCount:
      u32 objectEndOffset
      u8  payload[objectEndOffset - currentOffset]
```

Для всех 48 sector-файлов directory занимает 1512 байт. Structural probe подтвердил counts и вложенные `object → class → category → file` offsets без остатка. Число объектов на sector — от 4 до 585; для Gaul (`LVL001`) — 553, 177, 191, 147 и 4.

`absoluteStartObjectId` нельзя полноценно проверить без соответствующего `LVL`: ID продолжает level objects, а для некоторых instantiation modes также предыдущие sectors.

## `LVLnn.KWN` и защита PC-версии

Оригинальный PC XXL1 layout содержит DRM-зависимую область. Первые два `uint32` — служебное значение и размер/параметр защищённой области; это не magic и не version. Полный header включает число sectors и 15 таблиц классов с total/level counts и instantiation mode, после чего идут те же вложенные абсолютные end-offsets по категориям и классам.

В исследованной установке executable пропатчен для запуска, но сами девять `LVL` остаются в защищённом layout. XXL-Editor обрабатывает их отдельным patcher-путём и при необходимости получает расшифрованный header/DRM values извне. Поэтому probe сейчас безопасно фиксирует prefix и статус `headerRequiresDrmExtraction`, но не объявляет байты после prefix достоверной таблицей.

Подтверждено исходным кодом, но ещё не воспроизведено собственным parser:

- 15 категорий классов;
- порядок payload-категорий `[0,9,1,2,3,4,5,6,7,8,10,11,12,13,14]`;
- `u16 totalCount`, `u16 levelObjectCount`, `u8 instantiation` для XXL1;
- абсолютные offsets категорий, классов и объектов;
- зависимость level parsing от глобальных объектов `GAME`.

Неизвестно до извлечения DRM header/values:

- точная семантика первого prefix word;
- вариант защищённого header именно в этой сборке;
- границы защищённой области и алгоритм получения DRM values;
- корректные counts/offsets девяти `LVL` без внешнего контекста.

## Structural probe

```sh
fvm dart run bin/importer.dart probe-kwn /path/to/STR01_00.KWN
fvm dart run bin/importer.dart probe-kwn-tree /path/to/AsterixXXL
```

Probe валидирует границы и offsets для `GAME`, `GLOC`, `LLOC` и `STR`, не декодируя payload. Для `LVL` он возвращает явно неполный статус защищённого layout. Выход — JSON, ошибки используют общий structured error contract импортёра.
