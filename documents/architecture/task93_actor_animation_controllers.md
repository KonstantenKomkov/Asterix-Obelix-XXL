# Единые animation controllers остальных actor profiles

## Результат

Оставшиеся после Астерикса 318 доказанных bindings собраны из принятого
`animation_bindings.v1.json` в канонический versioned resource
`asterix.actor-animation-controllers` версии 1. Ресурс содержит 56 профилей:

- 209 bindings Обеликса, Идефикса, врагов и scripted actors исполняются через
  controller dispatch;
- 46 world/UI/FX bindings исполняются через типизированный
  simultaneous-track adapter;
- 63 cinematic bindings исполняются через типизированный timeline adapter.

Каждое состояние хранит глобально уникальный selector ID, точный
actor/skin/costume/context, clip/dictionary/slot, loop/completion,
root-motion policy и стабильный deterministic variant key. Локальный fallback
запрещён compiler/gate. World event сохраняет сразу несколько состояний, если
authored событие запускает одновременные tracks; cinematic cue остаются
упорядоченными и не дополняются синтетическими состояниями.

Канонический ресурс:
[`actors.authored-graphs.v1.json`](../../assets/animation_graphs/actors.authored-graphs.v1.json).
Размер — 150 587 байт, SHA-256:
`3929cea647213a28336c5aaf2898114ebf583ddc1590effa9246d0491a7d8b05`.

## Runtime и package boundary

Slice extractor копирует ресурс рядом с графом Астерикса, asset pipeline
добавляет его в ASTPAK как `actor-animation-controllers`, а Metal runtime
обязательно проверяет schema version и точное покрытие 56/318 до запуска
сцены. Отсутствующий или неполный controller resource является ошибкой
загрузки, поэтому старый registry не может стать silent fallback.

Воспроизводимая сборка:

```sh
make task93-remaining-graphs \
  OUTPUT=assets/animation_graphs/actors.authored-graphs.v1.json
```

Unit regressions проверяют каноничность и точное покрытие, уникальность
deterministic variants, запрет fallback, два simultaneous tracks транзакции
магазина, упорядоченные cinematic cues и terminal states. Оригинальные
binary/assets в Git не добавляются.
