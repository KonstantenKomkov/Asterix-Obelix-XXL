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

Для Астерикса runtime восстанавливает tracks из interleaved RenderWare keyframe
chains и строит parent indices из HAnim push/pop flags. В LVL01 58-node clips
сопоставлены gameplay-состояниям так: `idle=0053`, `run=0035`, `jump=0031`,
`fall=0039`, `attack=0000`, `hurt=0009`, `death=0033`. Idle/run зациклены,
остальные clips clamp-ятся на последней позе до перехода state machine.

Каждый render frame вычисляет полную palette `world * inverseBind` для всех 58
bones, добавляет gameplay-position к root space и передаёт palette отдельным
Metal buffer binding только на draw Астерикса. Статическая сцена и debug markers
всегда получают identity bone. Если отсутствует хотя бы один state clip,
иерархия не совпадает с skin или joint/weight data невалидны, skinned mesh не
рисуется и остаётся безопасный player marker — повреждённая геометрия и T-pose
не считаются допустимым fallback.

Для `idle↔run` локальные joint transforms смешиваются до вычисления hierarchy и
inverse bind palette. Вес приходит из fixed-tick player snapshot, idle phase не
сбрасывается при начале движения, run phase зависит от фактической скорости, а
вся palette поворачивается по последнему ненулевому вектору движения. Это
сохраняет непрерывную позу при разгоне, остановке и повторном старте.
Run clip дополнительно обязан содержать заметное движение не менее чем в 20
bone tracks. Статические и малоподвижные turn poses не принимаются как
locomotion. RenderWare chain reconstruction включает исходную позу каждого
сустава при `time=0`; без неё двухфазные clips ошибочно становились статичными.

Четвёртые lanes исходного RenderWare `RwMatrix` содержат flags/padding, поэтому
inverse-bind loader принудительно восстанавливает homogeneous значения
`[3,7,11]=0`, `[15]=1`; иначе служебные биты превращаются в огромные float и
разрушают skinned geometry.

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

Native XCTest покрывает mid-clip sampling, RenderWare chain reconstruction,
HAnim hierarchy, parent-child palette, skin position и границы fog.
Locomotion regressions отдельно проверяют fixed-tick связь скорости/фазы/yaw и
визуальную непрерывность representative skinned vertex на `idle→run→idle`.
`flutter build macos --debug` компилирует runtime Metal source и
проверяет совпадение CPU/Metal vertex layouts. Полная проверка выполняется через
`make check`, `make native-test` и `make policy-check`.
