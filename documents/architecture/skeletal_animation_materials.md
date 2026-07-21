# Скелетная анимация и материалы

## Runtime

`animation_runtime.hpp` реализует независимые от Metal sampling track, shortest-path
quaternion interpolation, иерархическую joint palette, inverse bind matrices и
нормализованный four-weight skinning. Некорректные parents, пустые tracks,
нулевые quaternions, отсутствующие weights и индексы вне palette отклоняются.

Metal vertex stage принимает joint indices, weights и palette. Статическая сцена
использует identity joint, а встроенная контрольная сцена непрерывно анимирует
верхнюю вершину вторым joint и тем самым проверяет весь GPU draw path без игровых
ресурсов. Повторно собранные importer proof и ASTPAK содержат полную skinned
geometry; старые локальные пакеты до задачи 28 содержат только skin weights и
должны быть пересобраны.

## Материалы

Runtime переносит vertex normals, RGBA material color, ambient/diffuse factors,
UV и mipmapped texture. Fragment stage выполняет направленное Lambert lighting,
alpha cutout, стандартное source-alpha blending и линейный distance fog. Цвет
тумана согласован с clear color сцены. Отсутствующие normals получают безопасную
вертикальную normal, а отсутствующая texture сохраняет material color.

Параметры освещения и тумана намеренно остаются runtime-константами до появления
извлечённых параметров окружения. Alpha blending включён для общего pipeline;
полная сортировка пересекающихся полупрозрачных поверхностей остаётся частью
последующего scene-specific effects pass, если visual regression выявит
артефакты.

## Проверка

Native XCTest покрывает mid-clip sampling, parent-child palette, skin position и
границы fog. `flutter build macos --debug` компилирует runtime Metal source и
проверяет совпадение CPU/Metal vertex layouts. Полная проверка выполняется через
`make check`, `make native-test` и `make policy-check`.
