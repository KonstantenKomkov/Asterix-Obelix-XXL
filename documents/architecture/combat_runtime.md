# Боевая система и первая комбинация

`combat::Runtime` — fixed-tick слой hit detection между state machine игрока и
будущим AI. Fighter имеет team, transform/facing, AABB hurtbox, health,
invulnerability timer и knockback velocity. Attack stage задаёт duration,
hit/input windows, локальный hitbox, damage и knockback.

Первая комбинация состоит из трёх stages. Каждый stage длится 0,55 с; первый
hit window — 0,14–0,28 с, input buffer — 0,28–0,50 с. Следующий stage начинается
только при нажатии внутри input window. После последнего или одиночного удара
добавляется recovery 0,10 с, поэтому новый старт возможен через 0,65 с. Эти два
значения соответствуют эталону: базовая атака 0,55 с (0,45–0,70) и минимальный
наблюдаемый интервал 0,65±0,10 с.

Размеры hitbox и окна второго/третьего stages не извлечены из оригинальных
данных и остаются конфигурируемыми стартовыми параметрами. Damage stages равен
1/1/2. Один stage может поразить fighter только один раз; team/self/dead targets
исключаются. Успешный hit уменьшает health, включает 0,4 с i-frames и задаёт
направленный knockback. Runtime публикует attack-started, combo-queued, hit и
defeated events.

Metal runtime регистрирует Астерикса как fighter, передаёт transform/facing и
фронты attack input, а переход combo stage перезапускает attack animation state.
HUD snapshot показывает stage и active hit window. Противник намеренно не
создаётся: perception, enemy attack orchestration и допустимая область входят в
задачу 36.

Unit regressions проверяют единственное попадание за stage, health, knockback,
i-frames, запрет раннего combo input, последовательность всех трёх stages и
завершение recovery.
