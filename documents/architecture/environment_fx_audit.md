# Аудит environment FX первого уровня

## Покрытие исходных данных

Importer сохраняет для каждой sector scene-node class ID, object ID, section,
полный source payload в hex, его размер, длину разобранного общего префикса и
SHA-256. Это позволяет отличить действительно статическую ноду от неизвестного
class-specific хвоста. Локальная повторная экстракция четырёх игровых секций
дала 60 нод классов 2, 3, 9, 19, 21 и 26, включая terminal sector root
`STR01_04`.

Фактически найдено 12 `CParticlesNodeFx`: 11 в `STR01_00` и ещё одна в
`STR01_03`, а не только 11 из первоначального proof. Все 12 включены, имеют
ненулевой authored state и сопоставлены с двумя ASTPAK `environment-fx`
resources и Metal camera-facing transparent particle draw path.

Класс 21 — `CAnimatedNode` со skeletal frame hierarchy — относится к уже
принятому skeletal pipeline и исключён из non-skeletal остатка. Класс 26 —
`CFogBoxNodeFx`: семь объектов содержат динамические fog-volume параметры.
Этот механизм не поддержан и вынесен в п. 79. Пока он не реализован, pipeline
сохраняет явные `fog-volume` / `backlogTask: 79` metadata без mesh payload;
тем самым fog box не может незаметно отрисоваться как статическая геометрия.

## Машинная приёмка

Команда

```sh
fvm dart run bin/environment_fx_audit.dart PROOF_DIRECTORY FILE.astpak
```

выдаёт по каждой ноде object ID, section, source payload, механизм, imported
resource и renderer path. Она также проверяет level-hook water UV scroll,
отсутствие texture-sequence, vertex/material/light animation, полноту bindings
и наличие отдельной задачи с runtime/visual criteria для fog volumes.

Принятый локальный отчёт содержит 60 scene nodes, 12 particle emitters,
3 water UV-scroll draw ranges, 668 static prelit meshes и ноль необъяснённых
non-skeletal animated objects. SHA-256 отчёта:
`4cb827f5f9c434f776e39bc4379ad17d5f5cb9d024e21b14882e00037113a387`.
Сам отчёт, ASTPAK и исходные игровые payload не добавляются в Git.
