# ASTPAK и release animation-fidelity gate

## Результат

Задача 93.8 замыкает authored animation runtime на готовый локальный ASTPAK.
Новый `task93-release-gate` принимает fresh, cached и установленный пакеты,
принятые registry/acceptance п. 91, оба канонических graph-ресурса и локальный
runtime evidence. Gate завершается успешно только при одновременном выполнении
всех условий:

- fresh/cached/installed ASTPAK побайтно совпадают;
- embedded `animation-bindings`, `authored-animation-graph` и
  `actor-animation-controllers` присутствуют ровно по одному и канонически
  совпадают с принятыми ресурсами;
- graph digests и оба provenance digests валидны, а графы дают ровно 408
  authored selectors: 90 Астерикса и 318 остальных bindings;
- release cold start использует digest проверяемого установленного пакета,
  остаётся жив не менее пяти секунд и не содержит loader/runtime diagnostics;
- семь representative controller/adapter сценариев имеют точные
  selector/clip/dictionary/slot из упакованных графов, trace и pose acceptance,
  ноль heuristic/static selections и ноль silent fallback.

Runtime evidence и отчёт являются локальными метаданными приёмки. ASTPAK,
оригинальные и производные игровые ресурсы в Git не добавляются.

## Воспроизведение

```sh
make task93-release-gate \
  FRESH=/local/task93-release/fresh.astpak \
  CACHED=/local/task93-release/cached.astpak \
  INSTALLED="$HOME/Library/Application Support/AsterixXXL/gaul-stage-1.astpak" \
  REGISTRY=/local/task91/final/animation-bindings.task91.json \
  ACCEPTANCE=/local/task91/final/acceptance.task91.json \
  RUNTIME_EVIDENCE=/local/task93-release/runtime-evidence.json
```

Принятый fresh/cached/installed пакет имеет размер 69 044 356 байт и SHA-256
`69141f020cfd18042f0f0ee8c9fb145036e249cd5b382ba9dd8f13d13db38a0e`.
Канонические digests embedded graph-ресурсов:

- Asterix graph:
  `68e7a18c614cdcb4ee37f04a899a10c48ef768c1f8ded079c4bf205fb3509765`;
- actor graphs:
  `360518a7147f8de0dbbac7af42e6e20dbda3f8d6dc71d557237ffdf70dd55c70`.

Release cold start оставался жив шесть секунд без diagnostics. Отдельные
native tests приняли controller/pose/jump, enemy, scripted, world и cinematic
runtime, а Runner smoke загрузил свежий установленный пакет, все доказанные
профили и реальные clips `0031`/`0064` без `sceneError`.
