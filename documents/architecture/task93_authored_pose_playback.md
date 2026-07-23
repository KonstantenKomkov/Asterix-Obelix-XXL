# Authored pose playback Астерикса

## Fixed tick и render sampling

`AnimationController` остаётся единственным владельцем cursor, phase,
completion и cross-fade. Во время перехода cursor исходного clip продолжает
двигаться с его authored playback rate; целевой clip использует собственные
rate и initial phase. One-shot и terminal clips сэмплируют точную конечную
позу, loop clips оборачиваются по duration.

`animation_pose_runtime.hpp` получает предыдущий и текущий controller snapshot
и строит render-only pose для interpolation alpha. Сэмплирование не изменяет
controller и учитывает wrap loop cursor. При cross-fade смешиваются локальные
joint transforms двух клипов, после чего строится единая hierarchy/palette.
Поэтому render FPS не влияет на fixed-tick результат и новый кадр не
перезапускает clip cursor.

Граф поддерживает две явные phase policies: `restart` начинает target с
authored initial phase, `synchronized` переносит нормализованную phase source
clip в target. Канонический граф Астерикса пока сохраняет доказанные start/change
операции без недоказанной автоматической phase synchronization; policy доступна
controller для переходов, где она будет зафиксирована provenance.

## Root motion

Каждое graph state строго загружает одну из политик `inPlace`,
`physicsDriven`, `authored`. Motion root XXL1 — joint 1 (для синтетического
однокостного теста задаётся joint 0). Pose sampler удаляет его накопленное
перемещение из skeletal palette при всех политиках: render root всегда остаётся
на физической capsule.

Для `authored` sampler отдельно возвращает доказанное смещение motion root как
вход владельцу физики. Оно намеренно не применяется второй раз в renderer.
`inPlace` и `physicsDriven` возвращают нулевое authored displacement: движение
задаёт gameplay/capsule.

## Проверки

Native pose regressions проверяют joint transforms до, в середине и после
cross-fade, независимые playback rates и initial phase, advancing source
cursor, root-motion policies, synchronized phase и неизменность fixed-tick
snapshot при render cadence 30/60/120 Hz. Metal translation unit проходит
отдельную Objective-C++ syntax-проверку с ARC.
