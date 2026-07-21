# ASTPAK runtime asset package v1

Формат принят в [ADR-002](../architecture/adr-002-runtime-asset-package.md), а
машиночитаемый manifest описан
[JSON Schema](schemas/asterix-runtime-manifest-v1.schema.json). Реализация:
`lib/runtime/asset_package.dart`.

## Физическая раскладка

Все числа little-endian. Header v1 занимает 48 байт.

| Offset | Type | Значение |
|---:|---|---|
| 0 | `u8[8]` | `ASTPAK\r\n` |
| 8 | `u32` | container version = 1 |
| 12 | `u32` | header size = 48 |
| 16 | `u32` | manifest schema major = 1 |
| 20 | `u32` | manifest schema minor = 0 |
| 24 | `u64` | UTF-8 manifest byte length |
| 32 | `u64` | absolute payload start, aligned to 16 |
| 40 | `u64` | payload byte length |

Сразу после header расположен canonical compact JSON. Padding до payload заполнен
нулями. `resources[].offset` отсчитывается от payload start; каждый resource
начинается на 16-byte boundary. Package заканчивается на последнем байте payload,
trailing data в v1 запрещены.

## Manifest 1.0

Обязательные корневые поля: `format`, `schema`, `bundleId`, `objects` и
`resources`; `entryObjectId` необязателен. Objects содержат stable ID, kind,
source locator, payload references, object dependencies и optional metadata.
Resources содержат те же identity fields, относительные offset/length, SHA-256
и optional metadata.

Canonical encoding рекурсивно сортирует JSON object keys; arrays objects и
resources сортируются по ID, а reference arrays — лексикографически. Metadata
допускает только JSON null/bool/string/integer и finite floating-point values.

## Ошибки и безопасность

Reader до возврата package проверяет magic/version, точные границы manifest и
payload, alignment/ranges каждого resource, соответствие ID source locator,
уникальность IDs, все ссылки и SHA-256. Ошибки имеют устойчивый
`AssetPackageErrorCode`. Команда ниже печатает manifest только после полной
проверки пакета:

```sh
make package-inspect INPUT=/path/to/package.astpak
```

Тесты используют только созданные для проекта синтетические payload. Оригинальные
и производные игровые ресурсы не хранятся в Git.
