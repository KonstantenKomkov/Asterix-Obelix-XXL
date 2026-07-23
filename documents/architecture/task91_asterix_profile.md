# Authored animation profile Астерикса

## Результат

Для `CKHkAsterix` восстановлены все 90 gameplay bindings словаря
`CKHkHero.heroAnimDict` (dictionary 0). Export соединяет numeric runtime
binding, dictionary slot и authored clip и отклоняет неполный профиль,
повторный clip, другую версию модуля или разрыв предыдущих anchor/dispatch
evidence.

Одинарный и двойной прыжки имеют разные статические и input chains:

| Действие | Input trace | State handler RVA | Slot read call RVA | Slot | Clip |
|---|---|---|---|---:|---|
| single jump | `jump.press → fixedTick` | `0x0008e8a0` | `0x0008ed5f` | 13 | `clip-0031` |
| double jump | `jump.press → fixedTick → jump.release → jump.press → fixedTick` | `0x0008e700` | `0x0008e889` | 35 | `clip-0064` |

Оба call sites проверяются как прямые вызовы доказанного slot-read primitive
`0x0008d650`. Общий `airborne` label и preview в доказательстве не
используются.

## Воспроизводимость

```sh
make task91-asterix-profile \
  GAME_DIR="/path/to/AsterixXXL" \
  ANCHORS="$HOME/asterix-reference/reverse-engineering/task91/anchors/run-a.json" \
  DISPATCH="$HOME/asterix-reference/reverse-engineering/task91/dispatch/run-a.json" \
  OUTPUT="$HOME/asterix-reference/reverse-engineering/task91/asterix/run-a.json"
```

Конфигурация находится в
[`asterix_profile.v1.json`](../../tools/task91/asterix_profile.v1.json).
Два независимых metadata-only export побайтно совпали; SHA-256:
`06b4a1e2ea23a9f09f7ee27c786847267ee0d49b4fa55d47beaf39e29fcbcd4a`.
Binary bytes, disassembly, pseudocode и локальные traces в Git не добавляются.
