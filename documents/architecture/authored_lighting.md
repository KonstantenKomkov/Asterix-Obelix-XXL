# Authored lighting Gaul

**Проверено:** 22 июля 2026.

## Исходный механизм

Аудит всех четырёх `STR01_00…03.KWN` подтвердил, что статическая sector geometry
использует RenderWare `rpGEOMETRYPRELIT` (`geometry flags & 0x08`). RGBA лежит в
geometry struct сразу после заголовка, по четыре байта на каждую вершину.
Отдельной lightmap или shadow-textуры для этого пути нет. Binding не выводится из
имён: geometry object ID связывается с payload scene-node с исходным transform,
а triangle material ID — с разрешённым RenderWare material slot.

Importer сохраняет каналы без квантования как нормализованный
`prelightColors[vertex][rgba]`. Pipeline требует либо отсутствие authored массива
у geometry без флага, либо ровно один конечный RGBA `0…1` на каждую вершину;
повреждённый массив отклоняется и не заменяется глобальным светом.

Metal переносит RGBA в vertex buffer и интерполирует его в fragment stage.
Authored RGBA модулирует texture/material RGBA до alpha cutout/blending и
считается уже запечённым результатом fixed-function lighting. Повторный Lambert
для этого пути запрещён, иначе и дома, и улица затемняются дважды. Для geometry
без `rpGEOMETRYPRELIT` используется нейтральный `(1,1,1,1)` и прежний material
ambient + directional Lambert.

## Post-build gate

Свежий локальный ASTPAK содержит 668 authored-lighting mesh, 132 268
prelight-вершин и 668 material draw ranges. Минимальный RGB равен `0`,
максимальный — `1`; все vertex counts совпали, invalid bindings — `0`. Audit
публикует source sector, object ID, resource ID, payload SHA-256, vertex/material
counts и явный Metal consumption path для каждого mesh:

```sh
fvm dart run bin/asset_package.dart audit-slice-assets FILE.astpak
```

Cold-start review дополнительно обнаружил пропущенные level-local collision:
13 ground и 62 dynamic-ground mesh из `LVL01.KWN`. Они теперь входят в тот же
authored pipeline; checkpoint внутри дома разрешается на реальный level floor.
Итоговый пакет содержит 287 collision mesh / 10 558 triangles и стартует без
scene error.

Clean build перестроил 1352 transform и взял 47 неизменяемых entries из cache;
повторный build взял все 1399 entries из cache. Оба пакета имеют размер
68 578 756 байт и SHA-256
`0d6bcaf988d3f84086290757fa0d46c6d8d3dcf88b606a83f6b4c6614372c56c`.
Исходные KWN, производные ASTPAK и визуальные captures остаются вне Git.
