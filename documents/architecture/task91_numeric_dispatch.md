# Numeric state/event dispatch задачи 91

## Результат

Для зафиксированного `GameModule.elb`
`35e780a40e4ee625430cb37982deebd085960c37091f3a60465c5aa207ab58a0`
восстановлен numeric dispatch всех 27 animation owners. Для каждого owner
зафиксирован numeric handler из доказанного vtable prefix. Пять обработчиков
используют индексированные jump tables:

| Dispatcher RVA | Кодирование входа | Ветвей |
|---|---|---:|
| `0x0008bc70` | старший байт минус 3 через lookup | 8 |
| `0x000cba50` | младший байт при старшем байте 76 через lookup | 18 |
| `0x000c3fc0` | младший байт при старшем байте 74 | 9 |
| `0x000f7560` | младший байт при старшем байте 73 | 22 |
| `0x001378b0` | вычисленный numeric index | 6 |

Экспорт содержит 63 пары `numeric index → branch target RVA` и две полные
lookup-карты. Адрес каждой таблицы проверяется по indexed-jump instruction,
а каждая извлечённая ветвь обязана указывать в executable section исследуемого
PE. Унаследованные handlers остаются отдельными owner-записями.

Semantic labels намеренно отсутствуют. Числовые входы нельзя называть
действиями до независимого input handler, именованного serialized event или
debugger trace; runtime animation registry этим gate не изменяется.

## Воспроизводимость

```sh
make task91-dispatch \
  GAME_DIR="/path/to/AsterixXXL" \
  ANCHORS="$HOME/asterix-reference/reverse-engineering/task91/anchors/run-a.json" \
  PRIMITIVES="$HOME/asterix-reference/reverse-engineering/task91/primitives/run-a.json" \
  OUTPUT="$HOME/asterix-reference/reverse-engineering/task91/dispatch/run-a.json"
```

Конфигурация находится в
[`numeric_dispatch.v1.json`](../../tools/task91/numeric_dispatch.v1.json).
Exporter отклоняет другой module hash, anchors/primitives другой версии,
изменившийся opcode или адрес jump table, выход lookup за диапазон и branch
target вне executable sections.

Два независимых metadata-only export побайтно совпали; SHA-256:
`82af9fd7a8b7e871036da675cae90736c34e7c18a7f331c94b347f45a3c875a0`.
Binary bytes, disassembly, pseudocode и локальный export в Git не добавлены.

## Граница следующего gate

Пункт 91.4 доказывает структуру numeric state/event dispatch, но не значения
действий. Пункт 91.5 должен связать числовые входы Астерикса с доказанными
input traces и отдельно довести single/double jump до dictionary/slot/clip.
