# Class/function anchors задачи 91

## Результат

Для зафиксированного `GameModule.elb`
`35e780a40e4ee625430cb37982deebd085960c37091f3a60465c5aa207ab58a0`
восстановлена воспроизводимая карта 27 animation owners:

| Группа | Owners |
|---|---:|
| Управляемые герои | 3 |
| Enemies | 8 |
| Scripted actors | 2 |
| World/UI/FX | 12 |
| Cinematic | 2 |

Карта содержит 40 полей animation dictionaries или управляющих animation
indices и не содержит unresolved anchors. Для каждого owner доказаны:

- единственная class-registration string и обращение к ней;
- registration, scalar factory и array factory в форме `module + RVA`;
- точка записи vptr и vtable RVA;
- первые 15 адресуемых virtual slots либо весь более короткий префикс;
- category/class ID из registration record;
- declaring class, имя и declaration ordinal поля по XXL-Editor.

Полная граница vtable намеренно не заявляется: MSVC размещает соседние таблицы
без переносимого терминатора. Доказанный префикс достаточен как стабильная
точка входа для call graph п. 91.3, а расширять его можно только по xrefs и
поведению конкретного метода.

## Provenance

Layouts взяты из чистого checkout XXL-Editor revision
`d606cfccf8faa31287aa1326fa9d10c292c06157`. Для героев поле
`heroAnimDict` корректно относится к базовому `CKHkHero`; для конкретных turtle
owners учитываются унаследованные поля `CKHkTurtle` и дополнительные поля
derived class. `CKPlayAnimCinematicBloc.paAnimIndex` включён как доказанный
slot-index field, тогда как dictionary owner находится в
`CKCinematicSceneData.animDict`.

Конфигурация owners находится в
[`class_anchors.v1.json`](../../tools/task91/class_anchors.v1.json). Exporter
отклоняет другой hash модуля, иной revision или грязный checkout XXL-Editor.
Он публикует только RVA, числовые идентификаторы и layout provenance; binary
bytes, disassembly, pseudocode и проекты анализа остаются вне Git.

## Воспроизводимость

```sh
make task91-anchors \
  GAME_DIR="/path/to/AsterixXXL" \
  XXL_EDITOR="/path/to/XXL-Editor" \
  OUTPUT="$HOME/asterix-reference/reverse-engineering/task91/anchors/run-a.json"
```

Два независимых export дали побайтно одинаковый JSON с SHA-256
`7ef67b5e5a852cf3970f3fde848e84b039325255a6fe8d1ffa29eb559bf2ec80`.
Синтетические regressions проверяют registration record, переход factory к
constructor, vptr store, vtable prefix, class/category IDs и layout join.

Эта карта не присваивает animation slots семантические значения. Следующий
gate, п. 91.3, должен от доказанных owner/method/field anchors построить xrefs
до primitives чтения dictionary slot и запуска animation.
