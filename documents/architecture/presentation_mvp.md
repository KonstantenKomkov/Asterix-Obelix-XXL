# Presentation MVP

## Flow

Приложение проходит через короткий launch screen в адаптивное главное меню.
Меню поддерживает активный профиль, отдельные действия New Game и Continue и
сохранённые настройки. New Game начинает чистое состояние выбранного профиля;
Continue разрешён только при валидном versioned save и восстанавливает профиль
и checkpoint из него.

Имя активного профиля хранится отдельно от gameplay save в SharedPreferences.
Оно ограничено 32 символами. Сохранение gameplay остаётся авторитетным для
профиля, checkpoint и времени Continue.

## Окно, Retina и адаптивность

Настройка fullscreen отправляется через `asterix/window` в `MainFlutterWindow`.
macOS bridge сравнивает требуемое состояние с `NSWindow.styleMask` и вызывает
`toggleFullScreen` только при расхождении. Значение сохраняется вместе с другими
настройками и применяется при их загрузке.

Главное меню переключается между Row и прокручиваемой Column при ширине 720 pt.
HUD скрывает developer debug panel ниже 760 pt. Widget tests проверяют отсутствие
overflow на 560×420 и 1440×900 logical pixels. Native Retina path по-прежнему
переводит logical size в округлённый вверх physical drawable size и покрыт
Runner XCTest.

## Локализация и субтитры

`AppStrings` содержит русский и английский presentation copy. Выбранная locale
сохраняется, применяется к Material/Cupertino delegates и сразу перестраивает
launch/menu, settings, controls, HUD и pause overlay. Gameplay identifiers и
diagnostic counters намеренно не переводятся.

Субтитры управляются сохранённым переключателем. MVP показывает локализованный
opening subtitle с ограниченным временем жизни; timer отменяется при dispose.
Последующие cinematic/dialogue события смогут использовать тот же presentation
слой без зависимости native runtime от языка.

## Проверки

Widget flow покрывает launch, профиль, fullscreen method call, ru→en, переход в
gameplay и локализованный subtitle. Отдельные tests проверяют persistence locale
и два aspect ratios. Проверка реального перехода Space между macOS fullscreen и
оконным режимом остаётся частью ручной приёмки vertical slice в п. 42.
