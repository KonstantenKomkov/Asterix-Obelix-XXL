# Authored animation profiles world/UI/FX и cinematics

## Результат

Восстановлены все 13 world/UI/FX profiles и 46 bindings: каждый numeric
world state/event соединён с точным dictionary, slot и authored clip.
Двухдорожечный shop transaction проверяется как одновременный выбор slots 1 и
4, а не как один semantic alias.

Все 14 `CKCinematicSceneData` timelines соединены с отдельным script event и
63 точными cues. Для каждого cue доказано чтение
`CKCinematicSceneData.animDict` и индекса
`CKPlayAnimCinematicBloc.paAnimIndex`; exporter проверяет все slot reads
timeline, а не только первый cue.

Gate отклоняет другую версию модуля, разрыв class/field или numeric dispatch
anchors, неполный profile/timeline, несовпадение runtime и concrete selector,
небиективные event/cue tables и изменение ожидаемых totals. Semantic action
labels и visual preview доказательством не служат.

Для `CKGrpMecaCpntAsterix` и `CKHkInterfaceInGame`, где сериализованная ссылка
проходит через generic field, class registration, vtable и numeric handler
восстанавливаются непосредственно из зафиксированного PE; generic reference
не выдаётся за typed field.

## Воспроизводимость

```sh
make task91-world-cinematics-profile \
  GAME_DIR="/path/to/AsterixXXL" \
  ANCHORS="$HOME/asterix-reference/reverse-engineering/task91/anchors/run-a.json" \
  DISPATCH="$HOME/asterix-reference/reverse-engineering/task91/dispatch/run-a.json" \
  OUTPUT="$HOME/asterix-reference/reverse-engineering/task91/world-cinematics/run-a.json"
```

Конфигурация находится в
[`world_cinematics_profile.v1.json`](../../tools/task91/world_cinematics_profile.v1.json).
Два независимых metadata-only export побайтно совпали; SHA-256:
`9148607fa49b16f0bb138216d20b5c8657c2759a816918c30bf9c0f9a8a2e20f`.
Binary bytes, disassembly, pseudocode и локальные traces в Git не добавляются.
