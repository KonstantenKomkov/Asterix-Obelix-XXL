# Release-приёмка доказанных анимаций

Задача 92 замыкает metadata-only результат п. 91.10 на запускаемый ASTPAK.
Сборочный скрипт принимает четвёртым аргументом принятый локальный registry и
подменяет им обычный checked-in registry только внутри временного importer
proof. Исходные и производные игровые данные в Git не попадают.

## Воспроизведение

```sh
GAME_ROOT="$HOME/Downloads/Asterix & Obelix XXL (Triada)/prefix/drive_c/AsterixXXL"
TASK91="$HOME/asterix-reference/reverse-engineering/task91/final/run-a"
OUT="$HOME/asterix-reference/task92-release"

./scripts/build_slice_assets.sh \
  "$GAME_ROOT" "$OUT/fresh.astpak" "$OUT/cache" \
  "$TASK91/animation-bindings.task91.json"
./scripts/build_slice_assets.sh \
  "$GAME_ROOT" "$OUT/cached.astpak" "$OUT/cache" \
  "$TASK91/animation-bindings.task91.json"
cmp "$OUT/fresh.astpak" "$OUT/cached.astpak"
make task92-release-audit \
  INPUT="$OUT/fresh.astpak" \
  REGISTRY="$TASK91/animation-bindings.task91.json" \
  ACCEPTANCE="$TASK91/acceptance.task91.json"
```

Gate проверяет ровно один embedded `animation-bindings`, структурное совпадение
с принятым registry, его принятый SHA-256, 408 selectors, ровно 345 уникальных
authored animation resources, отсутствие missing/unknown clips, нулевые
unresolved/ambiguous/visual-only итоги и отдельные single/double jump
assertions (`0031`, `0064`).

## Принятый прогон

Fresh и полностью cached rebuild имеют размер 68 805 044 байта и совпадают
побайтно. SHA-256 обоих пакетов:
`2c9f093a8177934acbaec16deada90e05e9e37b76688f70b7108f6eb0de9dfd9`.
Установленный
`~/Library/Application Support/AsterixXXL/gaul-stage-1.astpak` побайтно
совпадает с fresh artifact.

Post-build animation gate сообщил 345 resources, 345 unique authored clips,
408 selectors, один точный registry и пустые missing/unknown списки. Общий
slice audit также прошёл. Runner smoke загрузил установленный пакет через
Metal runtime, принял все hero/character/world/cinematic profiles без
diagnostics, увидел все 90 authored clips Астерикса и отдельно открыл single
jump `0031` и double jump `0064`. Release-приложение прошло cold start и
оставалось живым без loader/runtime/fallback diagnostics.

При приёмке устранена скрытая зависимость порядка фаз от порядка ключей JSON:
canonical registry п. 91.10 сортирует ключи объектов, поэтому runtime теперь
валидирует значения фаз независимо от сериализации и выдаёт события в порядке
их числовой фазы.
