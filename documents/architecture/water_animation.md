# Анимация воды Gaul

## Подтверждённый механизм

Вода XXL1 использует material UV transformation. Это подтверждается двумя
независимыми признаками исходного формата: RenderWare Material Effects PLG
задаёт UV transformation как effect type 5, а два поля `CKHkWaterFall`
семантически являются множителями скорости UV по X и Y. Для поверхности не
обнаружен обязательный skeletal/vertex clip или texture sequence.

Pipeline распознаёт только шесть водных материалов первого уровня:
`a_tr_eau_mer_f01_p0`, `sfx_riviere`, `sfx_water_ani04`, `sfx_water_2`,
`sfx_cascade06a` и `ecume01_modif`. В mesh payload сохраняются механизм
`uv-scroll`, скорость обеих осей, начальная фаза, repeat addressing и источник
времени `simulation-time`. Остальные материалы не получают неявной анимации.

## Runtime и приёмка

Metal vertex shader прибавляет к исходным UV детерминированное смещение
`phase + speed × simulationTime`; исходные texture, alpha, filtering и addressing
остаются в material range. Общие simulation seconds входят в save presentation
state, поэтому pause не меняет фазу, restore возвращает её точно, а выгрузка и
повторная загрузка streaming section не перезапускают цикл.

Pipeline regression проверяет наличие полного UV-профиля без static fallback.
Native visual regression сравнивает две фазы, а затем проверяет неизменность на
pause и идентичность после restore и пересоздания streaming presentation.
