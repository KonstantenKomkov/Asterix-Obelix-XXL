# Коллизии мира и движение капсулы

## Данные

Importer proof теперь вызывает существующий прямой extractor `CGround`,
`CDynamicGround` и `CWall`, сохраняет `collision.json` и упаковывает его как
typed `collision` payload ASTPAK. Pipeline проверяет schema, конечность каждой
вершины и диапазоны triangle indices. SVG overlay остаётся локальным
диагностическим артефактом и в proof/ASTPAK не включается.

## Controller

Независимый C++20 `CapsuleController` работает на фиксированном timestep и
поддерживает:

- ground probe по triangle mesh и gravity;
- ограничение slope по normal;
- подъём на ступень в пределах `step_height`;
- итеративное разрешение пересечения со стенами и subdivision быстрого
  горизонтального движения против tunnelling;
- синхронное перемещение dynamic-ground triangles и перенос стоящего персонажа
  один раз на stable object ID, независимо от числа треугольников объекта;
- восстановление checkpoint при падении ниже `kill_y`.

Состояние содержит position/velocity, grounded flag, stable ground object ID и
явный признак fall recovery. Геометрические параметры конфигурируются и не
зашиты в импортёр. Collision runtime не зависит от Metal, Flutter или
оригинальных ресурсов.

## Проверка

Синтетический маршрут проходит пол, допустимый склон и ступень, после чего
упирается в стену без провала или застревания. Отдельный сценарий проверяет
движущуюся платформу и checkpoint recovery. Asset-pipeline test подтверждает,
что collision payload участвует в детерминированной сборке и cache accounting.

Полная ручная прогулка по Gaul требует ввода и player state machine из задач 32
и 33. До них критерий обхода проверяется детерминированным controller route и
тем, что все 212 ранее извлечённых collision meshes теперь доходят до runtime
package без игровых данных в Git.
