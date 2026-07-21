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
и будущая simulation используют один источник.
