# M1 importer proof

Единый сценарий собирает открытые промежуточные представления четырёх классов
ресурсов vertical slice Gaul из установленной пользователем PC-копии:

```sh
./scripts/extract_slice_proof.sh /path/to/AsterixXXL /path/to/new-output
```

Команда не принимает и не создаёт исправленные вручную бинарники. Она требует
исходные `LVL001/STR01_00.KWN`, `LVL001/LVL01.KWN`, `GameModule.elb` и
`LVL001/WINAS/WINAS8.rws`, а output directory из соображений воспроизводимости
не должен существовать до запуска.

| Результат | Открытый формат | Источник |
|---|---|---|
| `scene.json` | JSON: meshes, materials, scene nodes | `STR01_00.KWN` |
| `textures/*.png` + manifest | RGBA PNG + JSON | `STR01_00.KWN` |
| `animations/*.animation.json`, skins + manifest | JSON | `LVL01.KWN` + открытая metadata-копия в `GameModule.elb` |
| `audio.wav` | PCM S16LE WAV | `WINAS8.rws` |
| `manifest.json` | JSON index, schema version 1 | сценарий proof |

Сценарий намеренно собирает доказательство прямого импорта, а не окончательный
runtime package. Версионируемый runtime format и инкрементальный pipeline —
отдельные задачи 23–25.

## Локальная проверка

Чистый запуск на исследованной копии завершился без hex-редактора и ручной
правки. Получены 381 mesh и 27 scene nodes, 52 PNG textures, 345 animations,
38 portable skins и PCM stereo 48 kHz audio. Все пути результата перечислены в
корневом manifest; оригинальные и производные ресурсы остаются вне Git.
