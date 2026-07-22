# State machine Астерикса

Authoritative gameplay-состояние находится в C++ `player::Runtime` и обновляется
только fixed simulation tick. Состояния: `idle`, `run`, `jump`, `fall`, `attack`,
`hurt`, `death`. Имя состояния является ключом выбора animation clip; фактическая
таблица импортированных клипов подключается после подтверждения их семантики.

`Runtime` принимает action snapshot задачи 32 и двигает существующий
`CapsuleController`. Gameplay-скорость сразу принимает целевое значение и
тормозит после отпускания ввода, диагональ нормализуется, прыжок и атака
реагируют на фронт кнопки. Grounded и вертикальная
скорость capsule определяют jump/fall/landing, а fall recovery возвращает
машину в `fall` до повторного контакта с землёй.

Параметры оставлены конфигурируемыми по ограничениям эталона. После калибровки
задачи 60 run speed равен 4.32 world unit/s (2.4 H/s при 1 H = 1.8 world unit),
scripted acceleration 18 и deceleration 21.6. Snapshot отдельно публикует gait
`idle/walk/run` для animation graph. Gameplay locomotion сразу выбирает `run` и
эталонные 4.32 world unit/s при полном направленном вводе;
ускорение больше не используется как неявный gait selector. `walk` доступен
только через явный `LocomotionMode::scripted_walk`, который включает authored
скорость 1.8 world unit/s для scripted/cinematic-сцен. Возврат управления,
respawn и restore восстанавливают gameplay mode. Этот выбор принадлежит player
runtime и не зависит от level/spawn: regression повторяет старт Gaul и
контрольный collision-сценарий с другим object id. Jump velocity равна 8.4 при
gravity 24, attack 0.55 s,
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
скорости капсулы к `run_speed`; поэтому collision-limited и аналоговый ввод не
дают скольжения ног, а отпускание управления плавно смешивает текущую run-позу
с idle. Metal
применяет направление движения как root-space yaw ко всей 58-bone palette.

Точный сериализованный spawn Астерикса в Gaul пока не подтверждён. Runtime
временно выбирает первый walkable collision triangle; это явное ограничение
нужно заменить на импортированный checkpoint/spawn в задаче 37.
