# Каменный push/pull-блок Gaul

В `LVL01.KWN` находятся два hook `CKHkPushPullAsterix` (`category=2`,
`classId=147`). Importer читает базовую postponed-ссылку на `CNode`, четыре
authored-вектора и параметры hook. Для объектов 0 и 1 ссылки ведут на level
nodes 8 и 11 с исходными позициями соответственно
`(-7.820352, 3.079212, -5.310643)` и
`(-27.091726, 1.089171, 49.158550)`.

Собственная geometry node содержит узкую служебную металлическую деталь
`spec1_meta_bloc2_01_p0`. Видимый объект хранится в следующем парном geometry
slot: meshes 17 и 24 имеют одинаковую authored-геометрию каменного куба
(175 vertices, 118 triangles) и material/texture binding `it_bloc2_01_mt`.
Extractor принимает пару только при наличии этого material binding, поэтому
metal mesh больше не может молча стать визуальным fallback.

Связанные `CKFlaggedPath` задают допустимые ranges `0…11.863387` и
`0…8.612516` (у второго пути есть промежуточная точка `5.002115`). ASTPAK
сохраняет mesh, полный node transform, origin, нормализованную authored axis и
этот range. Metal создаёт `PushBlock` из этих данных. Fixed-tick runtime разрешает
контакт капсулы с объёмом 2.12×2.14×2.32, допускает перемещение только вдоль
axis, блокирует поперечное проникновение и хранит единый offset для interaction,
collision и вершин render mesh. Offset входит в checkpoint/persistent state;
старые saves без поля `pushBlocks` мигрируют к исходной позиции.

Pipeline regression проверяет исходную позицию, texture binding и отсутствие
metal fallback. Native regression фиксирует состояние до перемещения,
поперечный collision, push вдоль axis, положение после перемещения и restore.
Исходные KWN, извлечённые meshes/textures и собранный ASTPAK остаются вне Git.
