# Аудио vertical slice

## Контракт

`audio::Runtime` принимает события fixed-tick gameplay и преобразует их в
запросы `music`, `ambience` и `effects`. Восемь effect channels выбираются по
приоритету: шаг может быть отброшен при заполнении, а hit, checkpoint и death
вытесняют менее важный звук. Music и ambience являются отдельными loop beds и
не занимают effect channels.

События attack/hit поступают из combat runtime, enemy attack — из enemy runtime,
lever/reward/checkpoint — из interactive runtime. Шаг ставится на фазе run с
fixed-tick интервалом 0,34 с. Поэтому звуки не зависят от Flutter frame rate и
синхронизированы с authoritative gameplay/animation transition.

## macOS playback

`AsterixAudioEngine` использует `AVAudioEngine`: музыка подключена напрямую к
main mixer, окружение и восемь effect players — через `AVAudioEnvironmentNode`.
Listener следует gameplay camera; world-space cues используют HRTF и позиции
игровых объектов. Непозиционные reward/checkpoint/death используют equal-power
pan. Suspend/resume приложения останавливает и возобновляет тот же audio graph.

Первый `audio` payload проверяется как PCM16 RIFF/WAVE и читается непосредственно
из локального ASTPAK. Он используется для фоновых loop beds. Короткие cues пока
синтезируются в памяти: их можно заменить типизированными audio resources без
изменения gameplay contract. Оригинальные и производные аудиофайлы в Git не
хранятся.

## Настройки и диагностика

Flutter передаёт сохранённые `musicVolume` и `effectsVolume` одним method call
при запуске gameplay и после возврата из pause settings. Значения ограничены
диапазоном 0…1 независимо в Dart, C++ и playback layer. Stats snapshot публикует
`audioReady` и число активных effect nodes.

Native unit tests проверяют независимые шины, idempotent beds, clamp громкости,
channel priorities, вытеснение и освобождение каналов. Полная проверка реального
импортированного трека требует локального ASTPAK и аудиовыхода macOS.
