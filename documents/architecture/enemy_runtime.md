# Enemy runtime

Первый противник работает в том же fixed-tick цикле, что игрок, бой и камера.
Его authoritative-состояние хранит capsule body, направление, здоровье, таймеры
атаки и cooldown. Граф состояний включает `idle`, `pursuit`, `attack`, `stun`,
`death` и `returning`.

Противник замечает живого игрока в радиусе perception, преследует его по
collision surface и наносит урон один раз в момент impact активной атаки. После
выхода за leash или потери цели он возвращается к исходной точке. Удары combo
приходят через общий combat runtime, переводят противника в stun, передают
knockback в capsule controller и при нулевом здоровье фиксируют death.

Параметры perception, attack range/duration/impact/cooldown, скорость, leash,
stun, здоровье и урон находятся в `enemy::Config`. Второй capsule controller не
продвигает dynamic collision world повторно: мир обновляется ходом игрока один
раз за simulation tick.

Metal runtime создаёт одного противника рядом с player spawn, перебирая
кандидатные точки на допустимой поверхности. Его transform синхронизируется с
combat fighter, а state, health и position публикуются в диагностическом native
snapshot. Противник использует синтетическое runtime-представление; оригинальные
модели, анимации и производные ресурсы в репозиторий не добавляются.

XCTest покрывает perception, pursuit, attack, поражение игрока, stun, knockback,
death, leash return и победу игрока полной трёхударной комбинацией.
