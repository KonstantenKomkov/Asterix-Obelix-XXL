# HUD, pause and gameplay settings

Flutter получает gameplay statistics через один `asterix/metal-stats` event
snapshot с частотой 4 Hz. HUD не опрашивает нативные объекты на render frame и
показывает authoritative current/max health, reward count и контекстную
interaction hint. Performance counters остаются в отдельной диагностической
части того же snapshot.

Pause action обрабатывается по фронту общей input-системой. Flutter overlay
отправляет `setPaused` через существующий input method channel, после чего
`MetalViewportView` вызывает `suspend`/`resume` renderer. При resume фиксированный
simulation clock получает новый baseline, поэтому время, проведённое в меню, не
превращается в catch-up ticks. Pause menu позволяет продолжить игру, открыть
настройки или выйти в главное меню.

Настройки музыки и эффектов сохраняются через `SharedPreferences` и ограничены
диапазоном 0–1 как при чтении, так и при записи. Их фактическое применение к
audio mixer относится к задаче 40. Экран управления сохраняет keyboard/gamepad
bindings; для всех действий, включая `interact`, доступны клавиатура и
контроллер. Fullscreen и presentation-параметры относятся к задаче 41.
