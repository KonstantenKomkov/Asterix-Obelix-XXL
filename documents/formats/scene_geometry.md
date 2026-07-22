# Геометрия и scene nodes XXL1 PC

## Подтверждённый путь

Импортёр извлекает статическую геометрию и sector-local scene nodes напрямую из `STRnn_mm.KWN`. Для первого вертикального среза контрольным набором служат пять файлов `LVL001/STR01_00..04.KWN`.

```sh
fvm dart run bin/importer.dart extract-geometry-summary /path/to/STR01_00.KWN
fvm dart run bin/importer.dart extract-geometry /path/to/STR01_00.KWN > "$HOME/asterix-reference/metadata/STR01_00.scene.json"
```

Полный JSON содержит только декодированные числовые данные и хранится вне Git вместе с прочими локальными производными ресурсами.

## Mesh

Для `CKGeometry` (`category=10`, `classId=2`) декодируются:

- абсолютный object ID внутри таблицы класса;
- RenderWare frame list и parent index;
- positions и normals;
- authored vertex RGBA при RenderWare `rpGEOMETRYPRELIT` (`flags & 0x08`);
- все UV sets;
- triangle indices и material ID;
- границы вложенных RenderWare chunks.

Индексы проверяются относительно vertex count. Native console geometry, particles и неоднозначный выбор нескольких costumes завершаются structured error вместо частичного результата.

## Scene nodes

Для объектов `category=11` читаются локальная матрица 4×4 и raw object references `parent`/`next`. Для подтверждённых наследников `CSGBranch`/`CNode` также читаются `child` и ссылка на geometry. Ссылка декодируется как:

```text
bits 0..5   category
bits 6..16  classId
bits 17..31 objectId
```

Часть parent/geometry references ведёт в защищённый `LVL`, поэтому JSON сохраняет устойчивые IDs, но не объявляет такие ссылки разрешёнными без level context.

## Контрольные counts Gaul

| Sector | Mesh | Scene nodes | Вершины | Треугольники |
|---|---:|---:|---:|---:|
| `STR01_00` | 381 | 27 | 49 852 | 55 312 |
| `STR01_01` | 74 | 14 | 29 617 | 33 472 |
| `STR01_02` | 102 | 14 | 27 330 | 30 847 |
| `STR01_03` | 106 | 4 | 24 670 | 29 407 |
| `STR01_04` | 0 | 1 | 0 | 0 |
| **Итого** | **663** | **60** | **131 469** | **149 038** |

Структура сопоставлена с реализациями `CKAnyGeometry`, `RwGeometry`, `RwMiniClump` и `CKSceneNode` в [XXL-Editor revision d606cfc](https://github.com/AdrienTD/XXL-Editor/tree/d606cfccf8faa31287aa1326fa9d10c292c06157).
