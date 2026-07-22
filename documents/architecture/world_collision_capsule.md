# Коллизии мира и движение капсулы

## Данные

Importer proof теперь вызывает существующий прямой extractor `CGround`,
`CDynamicGround` и `CWall`, сохраняет `collision.json` и упаковывает его как
typed `collision` payload ASTPAK. Pipeline проверяет schema, конечность каждой
вершины и диапазоны triangle indices. SVG overlay остаётся локальным
диагностическим артефактом и в proof/ASTPAK не включается.

Все четыре sector payload сохраняются раздельно вместе с source path, object
ID, dynamic/wall transforms и SHA-256. Level extractor читает единственный
`CKHkAsterixCheckpoint` (2/193), проходит его authored scene-node hierarchy и
упаковывает полученную позицию отдельным typed `checkpoint` payload. Для Gaul
это node 23 и world position `(63,5; 3,2; 78,2)`; эвристический выбор ближайшего
к началу координат треугольника больше не участвует в runtime startup.

## Controller

Независимый C++20 `CapsuleController` работает на фиксированном timestep и
поддерживает:

- ground probe по центру и 12 точкам кругового footprint капсулы;
- ограничение slope по normal;
- подъём на ступень в пределах `step_height`;
- итеративное разрешение пересечения со стенами и subdivision быстрого
  горизонтального движения против tunnelling;
- синхронное перемещение dynamic-ground triangles и перенос стоящего персонажа
  один раз на stable object ID, независимо от числа треугольников объекта;
- восстановление checkpoint при падении ниже `kill_y`.

Состояние содержит position/velocity, grounded flag, stable ground object ID и
явный признак fall recovery. Геометрические параметры конфигурируются и не
зашиты в импортёр. Collision runtime не зависит от Metal, Flutter или
оригинальных ресурсов.

## Проверка и аудит установленного пакета

Native routes проходят пол, допустимый склон, ступень, общий triangle edge и
межсекторный зазор 0,18 world unit без потери grounded state; отдельные сценарии
проверяют moving ground, authored spawn и состояние до/после fall recovery.
Горизонтальный путь делится максимум на `radius × 0,5`, поэтому footprint
проверяется на каждом fixed-tick substep.

`asset_package.dart audit-slice-assets` читает именно готовый ASTPAK и выводит
source sector/resource hashes, полный object inventory, mesh/triangle counts,
transforms, параметры route gate и checkpoint binding. Принятый локальный пакет
содержит 212 meshes / 9423 triangles: STR01_00 — 90/2576, STR01_01 — 58/2789,
STR01_02 — 50/1084, STR01_03 — 14/2974. Clean и cached builds побайтно совпали
с SHA-256 `0c8c826c2e9faea380c56b6ab7e4f35abd1b739b2ec25766ae37d1df97ade631`.
Release cold start с этим пакетом прошёл без loader/runtime error. ASTPAK и
извлечённые игровые данные остаются вне Git.
