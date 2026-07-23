# П. 93.6 — Behavioural/pose-приёмка относительно оригинала

## Граница данных

Оригинальная запись и размеченные trace-файлы хранятся только локально:

```text
$HOME/asterix-reference/reverse-engineering/task93/acceptance/
  original/<scenario>.json
  runtime/<scenario>.json
  report.json
```

В Git находится только канонический
[`behavioural_pose_acceptance.v1.json`](../../tools/task93/behavioural_pose_acceptance.v1.json):
идентификаторы сценариев, обязательные маркеры, допуски, SHA-256 локальных
trace и исходного capture. Принятый capture — Take C, segment 03, SHA-256
`78f57505a1cc43cc3fcf7a5098ee68273460ff6924d317178dc02818daaf86fb`.
Видео, кадры и производные игровые ресурсы в репозиторий не добавляются.

## Формат trace и сравнение

`task93_behavioural_pose_acceptance.py` строго проверяет versioned trace
`asterix.behavioural-pose`. Каждый именованный sample содержит:

- время маркера;
- точный dictionary/slot/asset binding;
- normalized phase и transition ID;
- пять нормализованных экранных landmarks: head, обе кисти и обе стопы.

Перед сравнением gate проверяет канонический SHA-256 локального оригинального
trace и его связь с SHA-256 исходного capture. Runtime trace должен иметь ровно
тот же набор маркеров. Binding и transition сравниваются точно; время, phase и
евклидово расстояние landmarks — с допусками 40 мс, 0,08 и 0,035
нормализованного размера кадра. Поэтому совпадение номера клипа при неверной
фазе или силуэте не проходит.

Матрица содержит семь обязательных сценариев: прыжок на месте, в движении,
с удержанием, double jump, отдельные ascending/apex/descending/landing
контрольные точки, interrupt уроном и pause/resume без продвижения phase.

## Воспроизведение

Runtime exporter сохраняет projected landmarks из той же camera/view
конфигурации, binding/transition из `AnimationController::Snapshot` и время
fixed tick. После локальной фиксации пары каталогов gate запускается так:

```sh
make task93-behavioural-pose-accept \
  REFERENCE_DIR="$HOME/asterix-reference/reverse-engineering/task93/acceptance/original" \
  CANDIDATE_DIR="$HOME/asterix-reference/reverse-engineering/task93/acceptance/runtime" \
  OUTPUT="$HOME/asterix-reference/reverse-engineering/task93/acceptance/report.json"
```

Приняты все 7 сценариев. Отдельная native regression проходит single jump
через `select:jump`, dictionary 0 / slot 13 / `clip-0031`, сохраняет transition
и binding на физическом apex, проверяет разные takeoff/apex/landing joint
palette и только после приземления переходит в `select:idle`.
Канонический локальный report имеет SHA-256
`cf16a1b695648f6d7edad0b623ba0d0ef18de7460d9695377116bedcaecfeb24`.

Unit-тесты gate отдельно отклоняют правильный clip с неверной позой,
расхождения binding/transition/phase/time, изменённый reference digest,
другой source capture и неполную матрицу сценариев.
