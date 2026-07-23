# Versioned authored animation graph Астерикса

## Результат

Принятый behavioural provenance п. 93.1 компилируется в отдельный runtime
resource схемы `asterix.authored-animation-graph` версии 1. Ресурс содержит
ровно 90 состояний и 90 selector-переходов профиля `CKHkAsterix`; каждый узел
сохраняет binding, runtime-state, dictionary/slot/clip, playback rate,
initial phase, phase/events и root-motion policy. Каждый переход сохраняет
authored trigger/guard, start/change, completion, interrupt и blending, а
также evidence ID исходного provenance.

Схема находится в
[`authored_animation_graph.schema.v1.json`](../../tools/task93/authored_animation_graph.schema.v1.json),
принятый канонический ресурс — в
[`asterix.authored-graph.v1.json`](../../assets/animation_graphs/asterix.authored-graph.v1.json).
Parser/validator запрещает неизвестные и отсутствующие поля, несовместимую
версию, повторные или неоднозначные selectors, недостижимые states и ссылки
между actor profiles.

## Воспроизводимость

```sh
make task93-authored-graph \
  PROVENANCE="$HOME/asterix-reference/reverse-engineering/task93/asterix/run-a.json" \
  OUTPUT="$HOME/asterix-reference/reverse-engineering/task93/graph/fresh.json" \
  CACHE_DIR="$HOME/asterix-reference/reverse-engineering/task93/graph/cache"
```

Повторная сборка из независимого принятого `run-b.json` через заполненный cache
побайтно совпала с fresh export. Размер ресурса — 87 894 байта, SHA-256:
`47c2d557315c6cefe3b98957438ff4be4b0346f5bccd6b8c3f28d2151d6a9965`.
Cache адресуется digest канонического содержимого и перед использованием
повторно проходит parser/validator.

Ресурс содержит только metadata. Binary bytes, disassembly, pseudocode,
debugger traces, captures и игровые assets в Git не добавляются.
