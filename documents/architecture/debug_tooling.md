# Runtime debug tooling

## Управление

Flutter-панель `DEBUG` отправляет одну bit mask через MethodChannel
`asterix/metal-debug`. Режимы комбинируются и переключаются во время работы без
пересборки и пересоздания `MTKView`:

| Bit | Режим | Реализация |
|---:|---|---|
| 0 | Wireframe | `MTLTriangleFillModeLines` для scene geometry |
| 1 | Collision | красный line overlay из typed collision payload ASTPAK |
| 2 | Triggers | переключаемый слот; показывает 0, так как XXL1 Gaul не сериализует `CKTrigger` |
| 3 | Navmesh | переключаемый слот; показывает 0, подтверждённых navmesh-данных в срезе нет |
| 4 | Object IDs | стабильная hash-раскраска mesh по импортированному object ID |

Неизвестные старшие bits отбрасываются native renderer. Collision overlay
использует depth bias, чтобы линии не мерцали на совпадающих поверхностях.

## Счётчики

Существующий EventChannel с частотой 4 Hz публикует FPS, CPU submission time,
GPU execution time, Metal allocated bytes и frame count. Snapshot дополнен
активной debug mask и числом collision triangles; HUD также показывает
loaded/visible meshes, batches и resident sections. Покадровых Dart → native
вызовов для статистики нет.

Runtime shader compilation errors сохраняются в `sceneError` и имеют приоритет
над менее важной диагностикой отсутствующего asset package. Это позволяет
увидеть ошибку Metal source в HUD и Runner XCTest.

## Проверка

Widget test переключает wireframe chip без пересборки. Runner XCTest проверяет
все пять bits, маскирование неизвестных flags и готовность runtime-скомпилированного
Metal pipeline. Collision geometry загружается из синтетического ASTPAK в
pipeline tests; оригинальные данные в Git не добавляются.
