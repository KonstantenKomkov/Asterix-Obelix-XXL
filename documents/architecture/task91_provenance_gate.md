# Versioned provenance gate authored animation bindings

## Результат

Версионированная схема
[`provenance.schema.v1.json`](../../tools/task91/provenance.schema.v1.json)
фиксирует непрерывную metadata-only цепочку для каждого runtime binding:

`profile/binding → module hash + owner vtable/dispatch RVA → numeric
state/event → dictionary field/id → slot → authored clip`.

Строгий валидатор объединяет четыре принятых profile export п. 91.5–91.8 и
биективно сопоставляет их полному набору `runtimeProfiles` из
`animation_bindings.v1.json`. Gate принимает ровно 408 уникальных binding keys
и 408 уникальных evidence IDs. Он отклоняет:

- другую версию модуля или смешение версий между export;
- отсутствующую функцию, state/event, dictionary field, slot или clip;
- повторное либо лишнее evidence и runtime binding без evidence;
- `visual-only`, `membership-only`, неоднозначную или неподтверждённую запись;
- разрыв равенства dictionary/slot между selector и authored asset join.

Переиспользование одного authored clip разными runtime bindings разрешено:
биекция относится к runtime binding и его полной доказательной записи, а не к
уникальности clip.

## Воспроизводимость

```sh
make task91-provenance-gate \
  ASTERIX="$HOME/asterix-reference/reverse-engineering/task91/asterix/run-a.json" \
  CONTROLLED_HEROES="$HOME/asterix-reference/reverse-engineering/task91/controlled-heroes/run-a.json" \
  ENEMIES_SCRIPTED="$HOME/asterix-reference/reverse-engineering/task91/enemies-scripted/run-a.json" \
  WORLD_CINEMATICS="$HOME/asterix-reference/reverse-engineering/task91/world-cinematics/run-a.json" \
  OUTPUT="$HOME/asterix-reference/reverse-engineering/task91/provenance/run-a.json"
```

Повторный запуск использует четыре соответствующих `run-b.json`. Два
metadata-only результата побайтно совпали; SHA-256:
`f71e47e63439ef29e39a7aff955f32f0d45a770b53c2aed2b6adae825a01c943`.
Dataset остаётся вне Git; в репозиторий входят только схема, собственный
валидатор, синтетические негативные тесты и SHA-256 принятого результата.
Binary bytes, disassembly, pseudocode и локальные traces не публикуются.
