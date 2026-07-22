# Gameplay-камера

`camera::Runtime` обновляется тем же fixed tick, что player state и capsule.
Камера смотрит на authoritative позицию игрока, а target dead zone допускает
небольшое движение внутри кадра без дрожания. При выходе за границу target
сдвигается ровно настолько, чтобы игрок оставался в зоне управления.

Default FOV равен подтверждённым 70°, базовая дистанция — 10 world units.
Высота, target zones, follow sharpness, near distance, aspect ratio,
минимальный collision radius и collision padding конфигурируемы. AABB camera
zones могут переопределять весь набор параметров; первая совпавшая зона имеет
приоритет. Специальный FOV 120° автоматически не используется, поскольку его
gameplay-семантика в эталоне не подтверждена.

Collision avoidance представляет камеру консервативной сферой: её радиус не
меньше заданного collision radius и диагонали near plane, вычисленной из FOV,
near distance и aspect ratio. Swept-volume проверка сначала ограничивает путь
target → candidate, затем lateral путь от предыдущего fixed-tick position к
новому. Conservative advancement использует текущий минимальный зазор до
triangle world, поэтому не перескакивает даже бесконечно тонкую поверхность;
найденный контакт сохраняет дополнительный padding.
Таким образом, тонкие поверхности и углы не пропускаются точечным лучом, а весь
отрезок между snapshots безопасен для render-интерполяции. После исчезновения
контакта обычный exponential smoothing плавно возвращает камеру к desired
distance. Near distance сохраняет устойчивый view vector в тесном пространстве.

Metal renderer строит look-at matrix из camera snapshot и применяет runtime FOV
к projection matrix. HUD snapshot публикует FOV и признак collision limitation.
Unit regressions проверяют удержание игрока в target zone, длительное слежение,
zone override, near-plane clearance у тонкой стены, lateral follow в углу,
промежуточные render snapshots и плавный возврат после потери контакта.

Импортированные `CKCameraClassicTrack` пока используются как источник
подтверждённых FOV/distance, но object-to-route mapping шести камер не установлен.
До такой привязки runtime zones остаются новой конфигурацией и не объявляются
точным восстановлением неизвестных полей оригинала.
