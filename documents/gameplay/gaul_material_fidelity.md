# Fidelity материалов и геометрии Gaul

**Проверено:** 22 июля 2026.

## Исправления

- Triangle material ID теперь разрешается через RenderWare material slots до
  экспорта. Повторно используемый slot больше не выбирает материал по неверному
  индексу.
- Texture lookup нормализует регистр, путь и расширение имени. Отсутствующая
  привязка не подменяется случайной текстурой.
- Metal создаёт sampler из RenderWare filtering, mipmap и U/V addressing.
- Alpha base level классифицируется как opaque, binary cutout либо blended.
  Cutout использует порог 0,5; blended-диапазоны рисуются после opaque с
  depth-test без записи глубины.

Команда аудита воспроизводит проверку runtime-пакета:

```sh
fvm dart run bin/asset_package.dart audit-materials \
  "$HOME/Library/Application Support/AsterixXXL/gaul-stage-1.astpak"
```

## Результат на локальном Gaul ASTPAK

Проверены 663 mesh, 149 038 triangles и 663 material records. Все triangle и
material indices валидны, все texture bindings разрешены. Среди 293 уникальных
texture names обнаружены 89 binary-cutout и 33 blended textures; исходные
Gaul-материалы в этом пакете используют repeat addressing и не содержат
отдельных alpha-texture names.

Debug-приложение smoke-запущено с пересобранным локальным ASTPAK. В solid и
wireframe режимах проверены стартовые terrain, дома, дерево, растительность,
деревянные и металлические объекты и animated mesh Астерикса. Силуэты и
назначение материалов сопоставлены с локальной эталонной записью: случайных
texture bindings, нетекстурированных mesh и marker fallback персонажа нет.
Точное совпадение стартовой камеры/spawn и автоматическое сравнение кадра входят
в п. 53.

Оригинальные изображения, запись и производный ASTPAK остались вне Git.
