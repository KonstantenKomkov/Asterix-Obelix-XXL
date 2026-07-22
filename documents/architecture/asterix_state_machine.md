# State machine Астерикса

Authoritative gameplay-состояние находится в C++ `player::Runtime` и обновляется
только fixed simulation tick. Состояния: `idle`, `run`, `jump`, `fall`, `attack`,
`hurt`, `death`. Имя состояния является ключом выбора animation clip; фактическая
таблица импортированных клипов подключается после подтверждения их семантики.

`Runtime` принимает action snapshot задачи 32 и двигает существующий
`CapsuleController`. Скорость разгоняется и тормозит к целевой, диагональ
нормализуется, прыжок и атака реагируют на фронт кнопки. Grounded и вертикальная
скорость capsule определяют jump/fall/landing, а fall recovery возвращает
машину в `fall` до повторного контакта с землёй.

Параметры оставлены конфигурируемыми по ограничениям эталона: run speed 2.4,
acceleration 10, deceleration 12, jump velocity 8.4 при gravity 24, attack 0.55 s,
hurt и invulnerability 0.4 s. Damage переводит в `hurt` или терминальный `death`;
повторный damage в invulnerability window игнорируется. Hitbox, combo windows и
источник enemy damage относятся к задаче 35.

Metal runtime создаёт игрока на collision payload, пакетно принимает input и
публикует state, health и position в существующем UI snapshot. Unit regressions
проверяют полный locomotion-маршрут, one-shot attack, hurt, invulnerability и
death lock.

Locomotion snapshot дополнительно хранит фактическую горизонтальную скорость,
последнее устойчивое направление, непрерывные таймеры idle/run clips и вес
перехода длительностью 0,12 с. Run phase масштабируется отношением текущей
скорости капсулы к `run_speed`; поэтому разгон и торможение не дают скольжения
ног, а отпускание управления плавно смешивает текущую run-позу с idle. Metal
применяет направление движения как root-space yaw ко всей 58-bone palette.

Точный сериализованный spawn Астерикса в Gaul пока не подтверждён. Runtime
временно выбирает первый walkable collision triangle; это явное ограничение
нужно заменить на импортированный checkpoint/spawn в задаче 37.
