# ADR-002: собственный runtime-контейнер ASTPAK

- **Статус:** принято
- **Дата:** 21 июля 2026 года
- **Задача:** 23

## Контекст

Importer proof создаёт meshes, textures, scene nodes, skins, animations,
collision, spatial regions и audio. glTF 2.0 хорошо описывает часть render
данных, но collision, streaming boundaries, gameplay object identity и audio
потребовали бы проектных extensions и отдельного корневого manifest. Runtime
также должен открывать один проверяемый файл и адресовать payload без JSON-файлов
и оригинальных путей рядом с приложением.

## Решение

Принят собственный little-endian контейнер `.astpak`. Он содержит фиксированный
versioned header, canonical JSON manifest и выровненный бинарный payload.
Manifest связывает runtime objects, их зависимости и typed resources через
устойчивые IDs. glTF/GLB не запрещён: pipeline может положить его в payload как
один из resource kinds, если это окажется выгодно для инструментов.

Формат реализован платформенно-независимой Dart-библиотекой builder/reader.
Writer сортирует objects/resources и JSON keys, поэтому одинаковый логический
input создаёт побайтно одинаковый пакет. Reader проверяет header, поддерживаемую
версию, ranges, source-derived IDs, ссылки и SHA-256 до выдачи payload.

## Устойчивые IDs

ID имеет вид `astx:<kind>:<128-bit lowercase hex>` и вычисляется как первые
128 бит SHA-256 от UTF-8 строки:

```text
asterix-stable-id-v1 NUL kind NUL normalized-source-path NUL source-key
```

`kind` и относительный source path приводятся к lowercase, `\` заменяется на
`/`; абсолютные пути, `.` и `..` запрещены. `source-key` — устойчивый locator
внутри исходного формата, например `geometry:17` или `(category,classId,index)`.
Байты payload в ID не входят: повторный импорт изменённого объекта сохраняет
identity, а целостность/изменение содержимого отражает отдельный SHA-256.

Переименование source locator создаёт новый объект. Collision IDs, два объекта
с одинаковым locator или совпадение ID object/payload завершают сборку ошибкой;
неявное переназначение запрещено. Будущие aliases/migrations должны добавляться
явно новой minor версией manifest.

## Версионирование

- `containerVersion` меняется при несовместимом изменении физической раскладки;
- `schema.major` меняется при несовместимом изменении manifest;
- `schema.minor` предназначен для обратно совместимых полей;
- v1 reader принимает только реализованные minor versions и отклоняет будущие;
- неизвестный resource `kind` может быть пропущен инструментом, но обязательная
  ссылка объекта на неподдерживаемый kind является ошибкой соответствующего
  runtime consumer.

## Последствия

Плюсы: один детерминированный файл, прямые ranges, общая identity для scene и
gameplay, checksum каждого payload, отсутствие зависимости runtime от glTF
extensions. Цена решения — собственные reader/writer и миграции schema. Глубокая
семантическая валидация, cache и incremental build относятся к задачам 24–25.
