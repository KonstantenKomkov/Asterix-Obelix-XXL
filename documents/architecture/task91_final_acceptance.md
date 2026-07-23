# Итоговая приёмка authored animation bindings

## Результат

Финализатор [`task91_final_acceptance.py`](../../scripts/task91_final_acceptance.py)
соединяет принятый provenance dataset п. 91.9 с локальным catalog и versioned
runtime registry. Для каждого из 408 runtime selectors он:

- находит ровно один non-fallback registry binding;
- сверяет authored clip с `assetJoin` доказательной записи;
- добавляет в локальный catalog точную связь profile/state-or-event →
  dictionary/slot/clip;
- добавляет ту же provenance-запись к selector обновлённого локального registry.

Gate принимает только digest provenance
`f71e47e63439ef29e39a7aff955f32f0d45a770b53c2aed2b6adae825a01c943`,
345 clips, 52 dictionaries и 518 slots. Итоговый отчёт требует ровно 408
confirmed bindings и нулевые unresolved, ambiguous и visual-only totals.
Визуальная сверка не используется как доказательство.

Single и double jump Астерикса проверяются отдельными обязательными
assertions:

- `asterix-player:jump` → dictionary 0 / slot 13 / `clip-0031`;
- `asterix-player:double_jump` → dictionary 0 / slot 35 / `clip-0064`.

## Воспроизводимость

```sh
make task91-final-acceptance \
  CATALOG="$HOME/asterix-reference/animation-catalog-cinematics-task62.6.json" \
  PROVENANCE="$HOME/asterix-reference/reverse-engineering/task91/provenance/run-a.json" \
  OUTPUT_DIR="$HOME/asterix-reference/reverse-engineering/task91/final/run-a"
```

Независимые запуски по `run-a` и `run-b` побайтно совпали. SHA-256:

- acceptance: `63d5f3b1d3dcf5e102ee4bc579304df6dea0746c3dfd541de92ff483bcb02c42`;
- обновлённый registry:
  `cd13b28efa8b5888dfd952ee1f7cbe75a5233f6b3cf573799ce507fff06cac24`;
- обновлённый catalog:
  `0dccfaf826ca9befa74617f976c185ca95764b7ce359e36f3f6f75de1798e54d`.

Catalog, registry export, acceptance dataset и исходный provenance остаются в
локальной рабочей области. В Git входят собственный финализатор, тесты,
описание и digests; оригинальные binary bytes, disassembly, pseudocode,
captures и извлечённые animation payloads не публикуются.
