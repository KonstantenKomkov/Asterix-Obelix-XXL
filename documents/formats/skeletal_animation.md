# Скелет и анимация XXL1 PC

## Источники

Общие анимации и `CKSkinGeometry` находятся в `LVLnn.KWN`. У оригинальной PC-версии таблица классов level header защищена, но её открытая копия присутствует в локальном `GameModule.elb`. Импортёр находит header по сигнатуре, читает payload из исходного `LVL` и не изменяет ни один исходный файл.

```sh
fvm dart run bin/importer.dart extract-animations \
  /path/to/LVL001/LVL01.KWN /path/to/GameModule.elb \
  "$HOME/asterix-reference/animations/LVL01"
```

Результат — JSON с ключевыми кадрами, тремя контрольными samples каждого clip, HAnim hierarchy, vertex bone indices/weights и inverse bind matrices. Производные данные сохраняются вне Git.

## Animation manager

`CAnimationManager` (`category=13`, `classId=8`) содержит `RwAnimAnimation` chunks (`0x1B`): version, scheme, flags, duration и keyframes. Поддержаны схемы 1 (float quaternion/translation, frame size 36) и 2 (16-bit compressed values, frame size 24). Число узлов определяется начальной последовательностью кадров с `time=0`; byte offset предыдущего кадра переводится в index через frame size.

Конвертер линейно интерполирует translation и quaternion с нормализацией, затем строит local 4×4 matrix. В `LVL01` подтверждены 345 clips; каждый успешно sampled в `t=0`, `duration/2` и `duration`.

## Skeleton и skin

Иерархия читается из HAnim extension `0x11E` frame list: node ID/index, hierarchy flags и keyframe size. Skin extension `0x116` содержит bone count, used-bone map, четыре bone indices и четыре weights на vertex, затем inverse bind matrices.

В `LVL01` найдено 39 `CKSkinGeometry`; 38 полностью конечных portable skins экспортируются. Один legacy object содержит non-finite float и не записывается как JSON: его object ID явно перечислен в `excludedNonFiniteSkinObjectIds`, чтобы повреждение не маскировалось. Для multi-costume объектов текущий proof экспортирует первый costume; полный выбор costumes остаётся задачей asset pipeline.

Структура сопоставлена с `RwAnimAnimation`, `RwExtHAnim`, `RwExtSkin`, `CAnimationManager` и `CKSkinGeometry` в [XXL-Editor revision d606cfc](https://github.com/AdrienTD/XXL-Editor/tree/d606cfccf8faa31287aa1326fa9d10c292c06157).
