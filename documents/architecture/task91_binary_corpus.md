# Binary corpus задачи 91

## Зафиксированная версия

Исследование выполняется только над одной локальной PC-установкой. Полный
машинный manifest хранится вне Git в
`$HOME/asterix-reference/reverse-engineering/task91/inputs/corpus.json`.
Инструмент не копирует содержимое исходных файлов и публикует только метаданные.

| Модуль | Размер | SHA-256 | PE | Timestamp | Image base |
|---|---:|---|---|---:|---|
| `Asterix.exe` | 73 728 | `b4e31e3e29015af6637f1fb1f3d326ac053453cbf4f7057bfc46ec3f83f9d1d9` | PE32 x86 | 1 082 707 822 | `0x00400000` |
| `GameModule.elb` | 3 117 056 | `35e780a40e4ee625430cb37982deebd085960c37091f3a60465c5aa207ab58a0` | PE32 x86 | 1 082 555 627 | `0x00400000` |

В корпус также входят все 108 KWN-файлов этой установки общим размером
227 802 491 байт. Их относительные пути, размеры и SHA-256 находятся только в
локальном manifest. Его SHA-256 после повторной генерации:
`af4f5a1a0603d91abdde00a669a4fe6da12d78b8c3f706fd6bf4d90d55408a25`.

Оба модуля не содержат PE debug directory или CodeView/PDB-ссылок; рядом с
установкой нет `.pdb` и `.map`. MSVC RTTI type descriptors стандартного вида
также отсутствуют, поэтому последующие anchors нельзя основывать на
предположении о сохранённом RTTI.

`Asterix.exe` содержит секции `.text`, `.rdata`, `.data`, `.rsrc` и импортирует
`ADVAPI32`, `KERNEL32`, `USER32`. `GameModule.elb` содержит `.text`, `_rwcseg`,
`.rdata`, `.data`, `_rwdseg`, `.rsrc`, четыре `.idr*` и `hack`; imports:
`ADVAPI32`, `d3d9`, `DINPUT8`, `DSOUND`, `GDI32`, `KERNEL32`, `ole32`,
`USER32`, `WINMM`. Полные RVA, размеры и flags секций находятся в manifest.

## Воспроизводимый запуск

Toolchain закреплён в
[`toolchain.v1.json`](../../tools/task91/toolchain.v1.json). Базовый
metadata-only analyzer не требует внешнего GUI и всегда требует несуществующий
`WORKSPACE`, то есть не может случайно переиспользовать результат:

```sh
make task91-headless \
  GAME_DIR="/path/to/AsterixXXL" \
  WORKSPACE="$HOME/asterix-reference/reverse-engineering/task91/run-01"
```

Для replay команда выполняется ещё раз с `run-02`. Совпадение
`run-01/analysis.sha256` и `run-02/analysis.sha256` доказывает одинаковый
metadata-only export двух чистых workspaces.
Оба принятых запуска дали analysis SHA-256
`287ed9e49d202ac512b309a040d8686984fc52a2d13ae38a73b1be3da30dc66c`.

Для анализа функций в п. 91.2 закреплены Ghidra 12.1.2, OpenJDK 21,
`x86:LE:32:default` и compiler spec `windows`:

```sh
TASK91_ANALYZER=ghidra make task91-headless \
  GAME_DIR="/path/to/AsterixXXL" \
  WORKSPACE="$HOME/asterix-reference/reverse-engineering/task91/ghidra-01"
```

Этот режим отклоняет другую версию Ghidra/Java и создаёт новые local projects.
Export содержит только identity модуля, язык, image base и число найденных
functions; листинги, псевдокод и байты остаются локальными.

Corpus отдельно можно пересобрать без Ghidra:

```sh
make task91-corpus \
  GAME_DIR="/path/to/AsterixXXL" \
  OUTPUT="$HOME/asterix-reference/reverse-engineering/task91/inputs/corpus.json"
```

Смена любого module/KWN hash создаёт другой корпус и запрещает объединять
полученные позднее evidence с этой версией.
