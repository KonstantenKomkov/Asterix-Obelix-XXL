# Текстуры и материалы XXL1 PC

## Извлечение

Материалы читаются из RenderWare material list каждого `CKGeometry`. Sector texture dictionary извлекается из `CTextureDictionary` (`category=9`, `classId=2`) соответствующего `STR`.

```sh
fvm dart run bin/importer.dart extract-textures /path/to/STR01_00.KWN \
  "$HOME/asterix-reference/textures/STR01_00"
```

Команда без ручной правки создаёт PNG и `manifest.json` вне Git.

## Материал

Для материала сохраняются RGBA color, ambient/specular/diffuse, texture и alpha-texture names, filtering, U/V addressing, флаг mipmaps и material ID каждого треугольника. Texture name является устойчивой связью mesh ↔ dictionary. Повторно используемые RenderWare material slots не дублируются.

## Изображение

PC XXL1 sector dictionaries используют base-level `RwImage`:

```text
u32 width
u32 height
u32 bitsPerPixel
u32 pitch
u8  pixels[pitch * height]
if bitsPerPixel <= 8:
  rgba8 palette[1 << bitsPerPixel]
```

Подтверждены 4-bit и 8-bit indexed layouts. Каждый pixel index занимает байт, а palette содержит соответственно 16 или 256 записей. Palette alpha переносится в PNG. Код также поддерживает прямой RGBA32 layout и отклоняет неизвестные варианты structured error.

В пяти Gaul sectors находятся 131 dictionary entry с 85 уникальными именами: 111 изображений 4-bit и 20 изображений 8-bit. В sector dictionaries нет отдельной цепочки mip images; sampler flag просит mipmaps, поэтому pipeline должен генерировать их из base level.

## Контрольный результат

`STR01_00` автоматически дал 52 PNG. Контрольная текстура `tr_tromp_maiso_g01_p0` декодирована как валидный RGBA PNG 64×64 с 16-entry palette. Синтетический тест проверяет palette indices и сохранение полупрозрачного alpha.

Материалы Gaul ссылаются на 119 уникальных texture names. 85 имён присутствуют в доступных sector dictionaries; ещё 46 ссылок относятся к общему level/global набору (множества пересекаются), находящемуся в защищённом `LVL`. Ссылки экспортируются по имени, но pixels станут доступны после извлечения level dictionary из DRM-layout.

Структура сопоставлена с `CTextureDictionary`, `RwImage`, `RwMaterial` и `RwTexture` в [XXL-Editor revision d606cfc](https://github.com/AdrienTD/XXL-Editor/tree/d606cfccf8faa31287aa1326fa9d10c292c06157).
