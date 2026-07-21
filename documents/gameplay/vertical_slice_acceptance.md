# Приёмка vertical slice Gaul Stage 1

**Дата:** 21 июля 2026 года.  
**Результат:** M4 принят в границах первой итерации.

## Проверенная сборка

Локальный pipeline одной командой извлёк `STR01_00`–`STR01_03`, level
animations/skins и первый RWS segment. Полученный ASTPAK не добавлялся в Git:

- размер: 49 435 964 байта;
- SHA-256: `2efd694dcf2807bd474c0c7273df3a605022eaaa263c10b8ccc969c037438b03`;
- 663 mesh, 131 texture, 4 collision payload, 9 423 collision triangles;
- 345 animations, 38 skins и один WAV payload;
- четыре sector-local section ID; повторяющиеся object IDs между секторами
  остаются уникальными благодаря source-derived ASTPAK IDs.

## Результаты сценария

| Проверка | Результат |
|---|---|
| Запуск и загрузка | Пакет открывается напрямую с локального пути; sandbox denial и configuration error устранены |
| Старт и checkpoint | Выбирается валидная поверхность `STR01_00`, игрок начинает с 3/3 HP, checkpoint 13 активируется |
| Движение и камера | Клавиатурный input перемещает игрока по импортированной collision, камера следует authoritative position |
| Бой | Враг переходит idle/pursuit/attack, наносит damage; combo, hit, stun и death проходят native regression |
| Смерть и restart | Death terminal до interact; restart возвращает player/world/enemy к checkpoint baseline |
| Save/load | Autosave записал schema v2 с checkpoint 13, player/enemy и world state; restore покрыт Flutter и native tests |
| Звук | WAV bed загружается, а attack/hit/enemy/checkpoint/death events проходят через audio runtime и AVAudioEngine |
| Стабильность | Живой debug-прогон держал около 60 FPS; CPU frame 4–6 ms, GPU около 0,9 ms; crash не наблюдался |
| Ресурсы | Исходные и производные данные остались вне репозитория; resource policy прошёл |

## Сравнение с эталоном

FOV 70°, fixed tick 1/60 s, combat timings 0,55/0,65 s, damage/i-frames,
checkpoint rollback, pause semantics и save boundary соответствуют допускам из
`reference_parameters.md` и последовательности из `reference_behavior.md`.
Состав статического мира расширен до всех четырёх непустых секторов выбранного
этапа.

В первой итерации персонажи представлены хорошо различимыми runtime-маркерами,
а материалы без корректной per-batch texture binding получают стабильный
нейтральный цвет. Gameplay placement пока является минимальной orchestration
среза: один бой, lever, destructible, reward и checkpoint. Эти ограничения не
блокируют проверку систем M4, но являются обязательной частью content/fidelity
цикла п. 44 и должны учитываться в решении п. 43.

## Автоматические проверки

- `make check` — resource policy, FFI build, format, analyze и 48 Flutter tests;
- `AsterixEngine` XCTest — 25 tests;
- `Runner` XCTest — 7 tests;
- macOS debug build и загрузка реального многосекторного ASTPAK.

