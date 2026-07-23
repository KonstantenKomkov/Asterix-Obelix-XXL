# Behavioural provenance state machine Астерикса

## Результат

Metadata-only exporter дополняет 90 принятых bindings `CKHkAsterix` из п. 91
доказанными behavioural facts. Для каждого binding результат содержит trigger
и guard, start/change operation, completion и interrupt policy, blend,
playback rate, начальную phase и events, root-motion policy, а также непрерывную
ссылку `GameModule.elb + RVA → CKHkHero.heroAnimDict → slot → clip`.

Gate принимает только ровно 90 уникальных `confirmed` записей. Отсутствующая
часть behavioural policy, другая версия модуля, неверная цель animation
primitive, неполная dictionary chain, `unresolved` или `visual-only` запись
останавливают export.

## Воспроизводимость

```sh
make task93-asterix-behaviour \
  GAME_DIR="/path/to/AsterixXXL" \
  PROFILE="$HOME/asterix-reference/reverse-engineering/task91/asterix/run-a.json" \
  OUTPUT="$HOME/asterix-reference/reverse-engineering/task93/asterix/run-a.json"
```

Команда повторяется в независимой чистой локальной директории с `run-b.json`;
оба результата побайтно совпали; SHA-256:
`39d391e2933cf9da93a18c2c436170f9c9ba133e5387560854abf5b9e9e106ab`.
Конфигурация доказательных RVA и типизированных
policies находится в
[`asterix_behaviour.v1.json`](../../tools/task93/asterix_behaviour.v1.json).

Binary bytes, disassembly, pseudocode, debugger traces и captures остаются
локальными и в Git не добавляются.
