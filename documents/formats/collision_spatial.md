# Коллизии и пространственные данные XXL1 PC

## Извлечение

Sector collision mesh хранится в категории 12: `CGround` (class 18), `CDynamicGround` (19) и `CWall` (20). Команда экспортирует переносимый JSON и контрольный SVG-overlay, где visual geometry показана серым, а collision geometry — красным.

```sh
fvm dart run bin/importer.dart extract-collision /path/to/STR01_00.KWN \
  "$HOME/asterix-reference/collision/STR01_00.json"
```

Level-переходы `CKSas` (class 17) читаются из защищённого `LVL` через открытую таблицу в локальном `GameModule.elb`:

```sh
fvm dart run bin/importer.dart extract-level-spatial \
  /path/to/LVL001/LVL01.KWN /path/to/GameModule.elb \
  "$HOME/asterix-reference/collision/LVL01.spatial.json"
```

Исходники не изменяются, оригинальные и производные ресурсы не попадают в Git.

## Collision mesh

Общий `ICollisionMesh` содержит `u16` counts, triangle indices, float32 vertices, AABB в порядке high/low corner и два параметра поверхности. `CGround` добавляет infinite/finite wall edges и heights. `CDynamicGround` также хранит position, rotation, scene-node ID и transform 4×4. `CWall` использует прямую и обратную матрицы.

Импортёр проверяет object boundaries, сохранённый packed size и все triangle/wall indices. Пять Gaul sectors дали 212 meshes, 7 395 вершин и 9 423 треугольника. Контрольный `STR01_00` содержит 87 ground и 3 dynamic-ground meshes — всего 2 360 вершин и 2 576 треугольников.

## Spatial и triggers

Три level-объекта `CKSas` связывают сектора 1–4 парами AABB. Это подтверждённые пространственные области переходов/streaming.

Классы `CKTrigger`/`CKTriggerDomain`, присутствующие в более поздних регистрациях движка XXL-Editor, в таблице классов исследованного XXL1 Gaul отсутствуют. Поэтому импортёр не создаёт фиктивные «trigger volumes». Событийная логика XXL1 связана с hooks, conditions и секторами; её семантическое восстановление относится к каталогу контента и gameplay-задачам, тогда как задача 14 фиксирует подтверждённое пространственное представление.

Контрольный SVG-overlay создан напрямую из `STR01_00`: collision surface совпадает с проходимыми поверхностями visual mesh; декоративная геометрия закономерно остаётся только в сером слое.

Структура сопоставлена с `ICollisionMesh`, `CGround`, `CDynamicGround`, `CWall` и `CKSas` в [XXL-Editor revision d606cfc](https://github.com/AdrienTD/XXL-Editor/tree/d606cfccf8faa31287aa1326fa9d10c292c06157).
