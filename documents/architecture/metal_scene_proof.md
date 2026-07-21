# M2: тестовая Metal-сцена и Flutter HUD

**Статус:** подтверждено 21 июля 2026 года.

## Реализация

`AsterixMetalRenderer` создаёт Metal pipeline из встроенного минимального shader
source, vertex buffer цветного треугольника, перспективную камеру с FOV 70° и
`Depth32Float` attachment. Треугольник вращается вокруг вертикальной оси, а
проекция пересчитывается с учётом aspect ratio физического drawable.

Renderer измеряет сглаженный FPS, CPU submission time, GPU execution time,
число представленных кадров и `MTLDevice.currentAllocatedSize`. Фабрика
platform view публикует один агрегированный snapshot четыре раза в секунду через
`asterix/metal-stats`; Flutter HUD не выполняет покадровых native-вызовов.

Фабрика обязана явно передавать `MTLCreateSystemDefaultDevice()` в
`MetalViewportView(frame:device:)`. Одноаргументный унаследованный initializer
`MTKView` обходит initializer подкласса и оставляет `CAMetalLayer.device` равным
`nil`; это покрыто native regression-тестом вместе с успешным созданием scene
pipeline.

## Проверка производительности

Для M2 выбран доступный validation baseline: MacBook Pro с Apple M3 Max,
встроенный Retina display, viewport 800×600 logical / 1600×1200 physical,
profile-сборка Flutter. После прогрева HUD стабильно показывал 59,9–60,0 FPS при
целевых 60 FPS. Контрольный snapshot: CPU 0,28 ms, GPU 0,06 ms, Metal allocation
64,8 MiB.

Эти числа подтверждают только минимальную proof-сцену и не являются бюджетом
импортированной сцены. Более слабая release-модель macOS остаётся предметом
общей hardware matrix; при её выборе этот тест необходимо повторить без
изменения критерия 60 FPS.

## Воспроизведение

1. Запустить `make run-profile`.
2. Открыть «Новая игра» и оставить окно активным минимум на пять секунд.
3. Проверить вращение треугольника, HUD и FPS в диапазоне 59–61.
4. Изменить размер окна и убедиться, что перспектива и depth attachment
   продолжают работать без остановки счётчика кадров.

Оригинальные игровые ресурсы и производные данные в proof не используются.
