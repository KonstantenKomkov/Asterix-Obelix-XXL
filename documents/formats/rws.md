# RenderWare Audio Stream (`.RWS`) в XXL1 PC

## Область исследования

Спецификация получена прямым чтением всех 631 `.RWS` установленной локальной
PC-копии Asterix & Obelix XXL и сверкой с реализацией
[`RwStream`](https://github.com/AdrienTD/XXL-Editor/blob/d606cfccf8faa31287aa1326fa9d10c292c06157/rwsound.cpp)
и редакторами
[`IGMusicEditor`](https://github.com/AdrienTD/XXL-Editor/blob/d606cfccf8faa31287aa1326fa9d10c292c06157/EditorUI/IGMusicEditor.cpp) /
[`IGSekensEditor`](https://github.com/AdrienTD/XXL-Editor/blob/d606cfccf8faa31287aa1326fa9d10c292c06157/EditorUI/IGSekensEditor.cpp)
XXL-Editor. Оригинальные и декодированные звуки в Git не добавляются.

## Контейнер

Все числа — little-endian. Каждый RenderWare chunk начинается с трёх `u32`:
`tag`, размер payload и RenderWare library ID. У исследованной версии library ID
равен `0x1803FFFF` (RenderWare 3.6.0.3).

```text
0x080D RwStream
├── 0x080E RwStreamInfo
│   ├── stream parameters, UUID and 16-byte name (`Stream0`)
│   ├── segment records: marker count, aligned size and data offset
│   ├── parallel arrays: used data size, UUID and 16-byte segment name
│   └── substream/codec parameters and name (`SubStream0`)
└── 0x080F sectorized encoded bytes
```

Размер `0x080E` является границей chunk: после известных полей может быть
padding. `dataOffset` сегмента отсчитывается от начала payload `0x080F`.
`dataSize` учитывает только заполненные ADPCM-байты, `dataAlignedSize` — весь
занятый секторизованный диапазон. При декодировании после `usedSectorSize`
байтов следует перейти на следующий `streamSectorSize`, пропустив padding.

## Codec и параметры

Codec UUID во всех 631 файлах:
`936538ef11b62d43957fa71ade44227a` — Xbox IMA ADPCM, 4 bit/sample. Блок содержит
по 4 header-байта на канал и по 32 encoded bytes на канал, то есть
`36 × channels` bytes. Из блока используются 64 interleaved PCM16 frames.

| Назначение/path | Файлов | Параметры | Секторизация |
|---|---:|---|---|
| `LVLnnn/WINAS/WINASn.RWS` | 86 | stereo, 48 000 Hz | зависит от потока |
| `LVLnnn/WINAS/SPEECH/l/l_WINn.RWS` | 545 | mono, 44 100 Hz | 4096 bytes, из них 2052 encoded |

Первая группа — level music/audio streams, выбираемые индексом stream. Вторая —
локализованные банки речи: `l` — индекс языка, `WINn` — индекс `CKSekens`, а
`Segmentm` соответствует строке `m` этого sekens. Это подтверждается кодом
сборки банков в `IGSekensEditor`, а не выводится только из имён файлов.

Число сегментов лежит в диапазоне 1–21. Распределение по всей копии:
`1:321, 2:70, 3:65, 4:25, 5:30, 6:25, 7:15, 8:15, 9:10, 10:10,
11:10, 12:15, 13:10, 14:5, 21:5`.

## Loop points

У segment record есть `numMarkers` и pointer-like поле markers, но во всех 631
исследованных файлах `numMarkers == 0`. Другого loop-start/loop-end поля в
`RwStreamInfo` не обнаружено. Поэтому встроенные loop points для этой PC-копии
**отсутствуют**; циклическое воспроизведение музыки должно задаваться игровой
логикой, а не выдуманными границами контейнера. Границы речевых сегментов — это
отдельные реплики, не loop points.

## Реализация импортёра

`parseRws` валидирует chunk/container boundaries, один substream, audio
parameters, segment offsets и codec UUID. `decodeFirstSegmentToWav` удаляет
sector padding, декодирует Xbox IMA ADPCM и создаёт PCM S16LE WAV без внешнего
конвертера. CLI:

```sh
dart run bin/importer.dart inspect-rws path/to/input.RWS
dart run bin/importer.dart inspect-rws-tree path/to/game
dart run bin/importer.dart decode-rws path/to/input.RWS output.wav
```

Тест использует только созданный для проекта mono stream с одним нулевым ADPCM
блоком. Он проверяет metadata, WAV header/PCM и контролируемую ошибку повреждённой
границы chunk.

## Локальная проверка

Полный `inspect-rws-tree` прочитал 631/631 файлов без ошибок и дал ровно две
конфигурации из таблицы выше, один codec UUID, максимум 21 сегмент и ноль файлов
с markers. `LVL001/WINAS/WINAS8.rws` декодирован вне Git в WAV:

- PCM S16LE, stereo, 48 000 Hz;
- длительность по `ffprobe`: 6.990667 s;
- SHA-256 WAV: `b1b0b79961036ba70795748cb7636e93a53f302921a3ae7fa5f12fdbf96aafcd`.

Ограничение текущего CLI: команда proof экспортирует первый сегмент. Парсер уже
сохраняет metadata всех сегментов; выбор произвольной реплики можно добавить в
pipeline без изменения формата.
