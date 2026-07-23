# Animation access primitives задачи 91

## Результат

Для зафиксированного `GameModule.elb`
`35e780a40e4ee625430cb37982deebd085960c37091f3a60465c5aa207ab58a0`
восстановлены пять устойчивых runtime primitives:

| Primitive | Назначение | Прямые xrefs |
|---|---|---:|
| `animation.start_or_change` | запуск/смена clip с mode и blend-параметрами | 41 |
| `animation.blend_update` | обновление текущего blend | 2 |
| `animation.complete_dispatch` | рассылка completion callback | 6 |
| `cinematic.play_block` | чтение cinematic slot и запуск track | 0 |
| `cinematic.stop_block` | остановка и completion cinematic track | 0 |

Последние два primitive являются virtual entrypoints и поэтому не обязаны
иметь прямой `call rel32`. Отдельно зафиксированы три selector:
hero, generic и cinematic. Каждый selector содержит индексированное чтение
dictionary slot и достигает общего start/change primitive.

Экспорт строит полный список 49 прямых xrefs и кратчайшие call paths от
доказанных vtable-prefix anchors 27 owners. Для 20 owners присутствует прямой
статический путь. Семь записей корректно помечены
`dataOwnerOrIndirectDispatch`: leader/turtle/catapult dictionaries исполняются
унаследованным или косвенным handler, а `CKCinematicSceneData` является
владельцем данных, используемым `CKPlayAnimCinematicBloc`. Эти записи не
выдаются за прямые связи и будут раскрыты вместе с numeric dispatch в п. 91.4.

## Воспроизводимость

```sh
make task91-primitives \
  GAME_DIR="/path/to/AsterixXXL" \
  ANCHORS="$HOME/asterix-reference/reverse-engineering/task91/anchors/run-a.json" \
  OUTPUT="$HOME/asterix-reference/reverse-engineering/task91/primitives/run-a.json"
```

Конфигурация RVA и ожидаемых xref counts находится в
[`animation_primitives.v1.json`](../../tools/task91/animation_primitives.v1.json).
Exporter отклоняет другой module hash, anchors от другой версии, изменившееся
число xrefs и selector, который больше не достигает ожидаемого primitive.

Два независимых запуска с независимо полученными anchors дали побайтно
одинаковый JSON с SHA-256
`2d6f06c9018e9ff7624af249a26c9d6a5bd2c2577704e32bcd90cf25564c15c9`.
В Git не добавлены binary bytes, disassembly, pseudocode или локальный export.

## Граница следующего gate

Пункт 91.3 фиксирует только механизмы доступа и исполнения. Он не присваивает
numeric state/event семантические имена и не меняет runtime animation registry.
Пункт 91.4 должен раскрыть switch/jump tables и indirect dispatch, используя
эти primitives как доказанные конечные точки.
