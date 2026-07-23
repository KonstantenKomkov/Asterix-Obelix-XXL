# Authored animation profiles enemies и scripted actors

## Результат

Для `CKHkBasicEnemy` и составного `CKHkBasicEnemyLeader` восстановлены все 85
gameplay bindings: 41 selector basic Roman dictionary 48, 41 selector equipment
dictionary 27 и три selector body dictionary 28. Каждая запись соединяет
numeric state/event с точным dictionary, slot и authored clip.

Составной leader проверяется как единый owner. Для numeric states 0, 1 и 2
зафиксирован синхронный выбор body и equipment: exporter отклоняет отсутствие
любого из двух selectors. Остальные 38 equipment states не выдают себя за
двухкомпонентные.

Все 24 scripted profiles соединены с отдельным dictionary owner, уникальным
`scriptEvent`, numeric owner-local event, slot и authored clip. Два
`cinematic-scene` owner используют `CKCinematicSceneData.animDict`; остальные
22 — `CKHkAnimatedCharacter.animDict`. Эти owners не смешиваются с 14
cinematic scene-data timelines задачи 91.8.

Gate отклоняет другую версию модуля, разрыв class/field или numeric dispatch
anchors, неполный profile, несовпадение runtime slot и concrete selector,
неизвестный owner kind, повторный scripted event и изменение ожидаемых totals.
Semantic action labels и visual preview доказательством не служат.

## Воспроизводимость

```sh
make task91-enemies-scripted-profile \
  GAME_DIR="/path/to/AsterixXXL" \
  ANCHORS="$HOME/asterix-reference/reverse-engineering/task91/anchors/run-a.json" \
  DISPATCH="$HOME/asterix-reference/reverse-engineering/task91/dispatch/run-a.json" \
  OUTPUT="$HOME/asterix-reference/reverse-engineering/task91/enemies-scripted/run-a.json"
```

Конфигурация находится в
[`enemies_scripted_profile.v1.json`](../../tools/task91/enemies_scripted_profile.v1.json).
Два независимых metadata-only export побайтно совпали; SHA-256:
`d0b61ef953bce5757ec7676a196da2a446269cced5258d62cbb690afe0355a73`.
Binary bytes, disassembly, pseudocode и локальные traces в Git не добавляются.
