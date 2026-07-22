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

Состояния `idle`, `pursuit`/`returning`, `attack`, `stun` и `death` публикуют
семантические animation actions вместо номеров clips. Каждый переход увеличивает
actor-local счётчик; вместе с `animation_variant_seed` он даёт повторяемый выбор
варианта при одинаковой истории simulation. `animationPhase()` вычисляется из
fixed-tick state time: attack damage window использует ту же нормализованную
фазу `attackImpactPhase()`, locomotion зацикливает фазу, а one-shot состояния
ограничивают её моментом завершения.

XCTest покрывает perception, pursuit, attack, синхронизацию impact phase,
детерминированный выбор animation variant, поражение игрока, stun, knockback,
death, leash return и победу игрока полной трёхударной комбинацией.
