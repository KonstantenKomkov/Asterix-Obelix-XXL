# Фиксированный timestep симуляции

## Контракт

Gameplay simulation использует шаг `1/60 s`, независимо от частоты presentation.
`FixedTimestep` накапливает monotonic elapsed time, выполняет только целые ticks и
возвращает `interpolationAlpha()` для render state между предыдущим и текущим
authoritative состоянием. Render path не изменяет simulation state дробным
шагом.

За один представленный кадр разрешено не более восьми ticks. При большей паузе
целые просроченные шаги отбрасываются и учитываются в `droppedSeconds()`, чтобы
движок не попал в spiral of death; остаток меньше одного шага сохраняется для
интерполяции. Отрицательное и non-finite время отклоняется. Resume сбрасывает
точку измерения wall clock, поэтому время sleep/suspend не догоняется симуляцией.

## Интеграция

Metal proof больше не вычисляет animation pose непосредственно из wall clock.
Каждый `drawInMTKView` передаёт elapsed time accumulator-у, fixed ticks обновляют
предыдущее и текущее animation state, а vertex palette получает
интерполированную фазу. Тот же runtime предназначен для movement, collision и
gameplay state следующих задач.

## Проверка

Native regression выполняет одинаковый десятисекундный сценарий при presentation
30, 60 и 120 Hz. Во всех трёх случаях выполняется ровно 600 simulation ticks и
получается одинаковая позиция. Отдельный тест проверяет alpha между ticks и
ограничение catch-up после секундной задержки.
