# Анимация воды Gaul

## Подтверждённый механизм

Вода XXL1 использует material UV transformation. Видимая поверхность не входит
в sector meshes: два level hook `CKHkWaterFall` ссылаются на branch nodes 108 и
109, под которыми находятся geometry 44–46. Их материалы — `sfx_riviere` и
`a_tr_eau_mer_f01_p0`, а два float-поля hook задают authored UV-множители
`(0,3; 0,6)` и `(1,0; 0,5)`. RenderWare Material Effects PLG независимо
подтверждает UV transformation как effect type 5. Обязательный skeletal/vertex
clip или texture sequence для этих поверхностей не обнаружен.

Importer экспортирует hook, branch, три связанные geometry (449 vertices, 628
triangles), scene transforms, материалы, textures и оба множителя в
`water_surfaces.json`. Pipeline создаёт отдельные level mesh/scene-node bindings
и только им назначает `uv-scroll`; sector meshes `tr_sabl_river_*` остаются
дном/берегами и не получают неявной анимации. В mesh payload сохраняются обе
authored скорости, начальная фаза, repeat addressing и `simulation-time`.

## Runtime и приёмка

Metal vertex shader прибавляет к исходным UV детерминированное смещение
`phase + speed × simulationTime`; исходные texture, alpha, filtering и addressing
остаются в material range. Общие simulation seconds входят в save presentation
state, поэтому pause не меняет фазу, restore возвращает её точно, а выгрузка и
повторная загрузка streaming section не перезапускают цикл.

Pipeline regression проверяет наличие полного UV-профиля без static fallback.
Native visual regression сравнивает две фазы, а затем проверяет неизменность на
pause и идентичность после restore и пересоздания streaming presentation.

`asset_package.dart audit-slice-assets` проверяет готовый ASTPAK, а не proof:
для Gaul ожидаются 3 water surface bindings / Metal draw ranges, 628 triangles,
ноль sector fallback и два набора authored множителей. Тот же gate проверяет два
каменных push/pull-блока и их render/collision/interaction bindings.
