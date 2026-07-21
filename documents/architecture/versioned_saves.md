# Versioned vertical-slice saves

Сохранение разделено на portable Flutter envelope и authoritative native state.
Envelope schema v2 содержит `schemaVersion`, profile ID/name, checkpoint ID,
UTC timestamp и opaque `gameplayState`. JSON хранится в `SharedPreferences` под
ключом `verticalSliceSaveV2`; повреждённые и неизвестные будущие версии безопасно
игнорируются.

`SaveGame.decode` последовательно мигрирует legacy schema v1: плоские profile и
checkpoint поля преобразуются в v2 без изменения gameplay payload. Новые
миграции должны добавляться до строгой валидации целевой схемы и сохранять
неизвестные native state fields, если версия их поддерживает.

Native `captureState` атомарно копирует player position/checkpoint/health, enemy
position/health и mutable interactive state: reward counter, active checkpoint,
triggers, levers, destructible health и reward flags. `restoreState` проверяет
типы, размеры массивов, ID checkpoint и диапазоны здоровья до применения,
синхронизирует combat fighters и делает восстановленное состояние новым baseline
для death/fall rollback.

Flutter автоматически сохраняется при смене active checkpoint и при открытии
pause menu. При старте сохранение отправляется native-слою сразу; если ASTPAK ещё
загружается асинхронно, Swift bridge удерживает pending state и применяет его
после успешной публикации scene runtime. Это устраняет зависимость результата от
порядка создания platform view и завершения asset load.
