# Authored animation profiles Обеликса и Идефикса

## Результат

Для `CKHkObelix` и `CKHkIdefix` восстановлены все 100 gameplay bindings
словаря `CKHkHero.heroAnimDict` (dictionary 0): 72 binding Обеликса и 28
binding Идефикса. Каждый numeric runtime state/event сохраняет отдельную
запись, даже когда несколько slots выбирают один authored clip.

Gate отдельно фиксирует пять групп повторного использования:

| Owner | Authored clip | Dictionary slots |
|---|---|---|
| `CKHkObelix` | `clip-0151` | 18, 94 |
| `CKHkIdefix` | `clip-0176` | 0, 12, 89 |
| `CKHkIdefix` | `clip-0184` | 8, 9 |
| `CKHkIdefix` | `clip-0187` | 2, 5, 26 |
| `CKHkIdefix` | `clip-0190` | 14, 91 |

Exporter отклоняет другую версию модуля, разрыв class/field или numeric
dispatch anchors, неполный профиль, неизвестный named binding
и любое изменение ожидаемых reused-clip групп. Preview и сходство движения в
доказательстве не используются.

## Воспроизводимость

```sh
make task91-controlled-heroes-profile \
  GAME_DIR="/path/to/AsterixXXL" \
  ANCHORS="$HOME/asterix-reference/reverse-engineering/task91/anchors/run-a.json" \
  DISPATCH="$HOME/asterix-reference/reverse-engineering/task91/dispatch/run-a.json" \
  OUTPUT="$HOME/asterix-reference/reverse-engineering/task91/controlled-heroes/run-a.json"
```

Конфигурация находится в
[`controlled_heroes_profile.v1.json`](../../tools/task91/controlled_heroes_profile.v1.json).
Два независимых metadata-only export побайтно совпали; SHA-256:
`46f811f47fe8ff6a4168d28b4ebf44929c1cbc2d08a67b8694a64aba993a392a`.
Binary bytes, disassembly, pseudocode и локальные traces в Git не добавляются.
