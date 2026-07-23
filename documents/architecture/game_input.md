# Единый игровой ввод

`GameInputRouter` сводит клавиатуру и extended gamepad в actions, одинаковые для
gameplay и Flutter-паузы. Клавиатурная раскладка версионирована и хранится в
`SharedPreferences`; экран «Управление» позволяет переназначить каждое действие.

macOS использует системный `GameController.framework`, поэтому Xbox- и
PlayStation-совместимые устройства не определяются по vendor ID. Native слой
публикует нормализованные оси/кнопки и connect/disconnect. Disconnect немедленно
обнуляет controller state, а reconnect устанавливает handlers заново. Dead-zone
и gameplay-семантика движения остаются задачей state machine №33.

Каждое изменение публикуется одним snapshot через `asterix/game-input`, без
покадровых object calls. Escape и controller Menu образуют edge действия pause;
остальные actions продолжают обновляться при открытом pause overlay, поэтому UI
и simulation используют один источник.

## Canonical movement basis

Gameplay первого уровня использует world-space basis: `+X` — вправо, `-X` —
влево, `-Z` — вперёд по карте, `+Z` — назад. Фиксированная follow-камера не
вращает этот вектор. Keyboard actions, WASD, стрелки и left stick сначала
сводятся к единственной паре `(right - left, forward - backward)`. Player
runtime один раз преобразует её в map vector `(x, 0, -z)`, после чего
нормализует диагональ.

Facing вычисляется только из фактического горизонтального capsule displacement
на fixed tick как `atan2(displacement.x, -displacement.z)`. Тот же сохранённый
facing используют locomotion, combat hitbox и presentation; сырой input
повторно не интерпретируется. У authored skin
локальный forward равен `-Z`, поэтому Metal применяет единственное
преобразование `yaw = π - facing`. Оно учитывает map `-Z`, column-vector
convention матрицы и не требует компенсирующих инверсий по отдельным
направлениям.

Fixed-tick regression проверяет положительные dot products canonical input →
displacement, gameplay facing → displacement и authored model forward →
displacement для четырёх cardinal и четырёх diagonal направлений. Отдельно
проверено, что restore и respawn не меняют basis, а keyboard и gamepad дают
одинаковые actions.
