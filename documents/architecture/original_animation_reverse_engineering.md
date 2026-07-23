# Reverse engineering привязок анимаций оригинала

## Цель и границы

Работа восстанавливает доказуемые связи
`actor/state/event → animation dictionary → slot → clip` из законно
установленной локальной копии Asterix & Obelix XXL. Итогом служат собственные
таблицы фактов, валидаторы и обновлённый runtime registry, а не перенос
реализации оригинального executable.

Исходные executable, дампы, проекты декомпилятора, листинги, псевдокод и
фрагменты оригинальной реализации остаются вне Git. В репозиторий допустимо
добавлять только:

- SHA-256 и PE-метаданные исследованной версии;
- стабильные идентификаторы функций и таблиц в форме `module + RVA`;
- тип наблюдения и краткое описание потока данных без машинного кода;
- восстановленные числовые state/event/dictionary/slot связи;
- собственные инструменты проверки и синтетические тесты.

Если обнаруживается защита от анализа или для результата требуется копирование
реализации оригинала, работа останавливается до юридической оценки.

## Локальная рабочая область

Рекомендуемый каталог:

```text
$HOME/asterix-reference/reverse-engineering/task91/
  inputs/            # хеши и локальные пути, без копирования в Git
  projects/          # Ghidra/другой проект анализа
  exports/           # локальные call graph, xrefs и таблицы наблюдений
  evidence/          # machine-readable evidence для acceptance
  reports/           # локальные отчёты и unresolved queue
```

Минимальный набор входов:

- `GameModule.elb`;
- `Asterix.exe`;
- соответствующие level/global KWN-файлы;
- исходный код XXL-Editor как независимое описание сериализованных классов.

Перед анализом фиксируются SHA-256, размер, PE timestamp, image base и sections.
Разные версии binary нельзя объединять в одну цепочку доказательств.

## Доказательная модель

Одна подтверждённая запись должна содержать:

```text
binding key
  actor + runtime state/event + context
source identity
  module SHA-256 + function/table RVA
dictionary access
  доказанный owner/field + dictionary identity
slot selection
  константа, ветвь switch/table либо прослеженное вычисление
asset join
  dictionary slot → локальный clip ID из импортёра
confidence
  confirmed
```

Для `confirmed` обязательна непрерывная статическая цепочка от обработчика
состояния/события до чтения конкретного dictionary slot. Название класса,
dictionary membership, сходство движения, preview или runtime selector нового
движка сами по себе доказательством не являются.

Допускаются два независимых способа усиления статического вывода:

- debugger trace точки чтения slot при воспроизводимом вводе;
- controlled data perturbation в локальной копии с наблюдаемой сменой только
  ожидаемого действия.

Они не заменяют статическую цепочку и не публикуются как оригинальные данные.

## Последовательность исследования

### 91.1 — Зафиксировать binary corpus и toolchain

Создать локальный manifest входов и воспроизводимую конфигурацию headless
analysis. Проверить architecture, image base, sections, imports, RTTI и
отсутствие PDB/MAP/debug directory. Результат: corpus report и команды
повторного анализа для точной версии binary.

### 91.2 — Восстановить class/function anchors

По MSVC RTTI, constructors, vtables и class-registration strings найти
`CKHkAsterix`, `CKHkObelix`, `CKHkIdefix`, enemy, scripted, world и cinematic
owners. Сопоставить поля объектов с layout из XXL-Editor. Результат: локальная
карта `class → vtable → methods → animation dictionary field`.

### 91.3 — Найти animation access primitives

Восстановить функции получения dictionary slot, запуска/смены animation,
blend/complete callbacks и cinematic play blocks. Определить сигнатуры вызовов
и все xrefs. Результат: проверяемый call graph от gameplay owners к чтению
слота.

### 91.4 — Восстановить state/event dispatch

Для каждого owner выделить numeric state, event handlers, switch/jump tables и
переходы. Не присваивать semantic label до доказанного входа: input handler,
именованного serialized event либо наблюдаемого debugger trace.

### 91.5 — Закрыть Астерикса и отдельно оба прыжка

Сначала восстановить полный профиль Астерикса. Для одинарного и двойного
прыжка требуются разные воспроизводимые input traces и две независимые цепочки
до dictionary/slot/clip. Gate не принимает общий `airborne` label или выбор по
preview.

### 91.6 — Закрыть остальных управляемых героев

Восстановить профили Обеликса и Идефикса, включая locomotion, combat,
interaction, damage/death и water/swim. Повторно используемые clips сохраняют
раздельные state/event bindings.

### 91.7 — Закрыть enemies и scripted actors

Восстановить basic Roman, составного Roman leader и 24 scripted dictionary
owners. Для составного персонажа отдельно доказать синхронный выбор body и
equipment slots.

### 91.8 — Закрыть world/UI/FX и cinematics

Восстановить 13 world profiles и 14 cinematic scene-data timelines. Для
одновременных tracks доказать все slot reads, а не только первый cue.

### 91.9 — Встроить provenance gate

Добавить versioned evidence schema и валидатор, который биективно соединяет
каждый runtime binding с source identity, state/event, dictionary, slot и clip.
Gate отклоняет visual-only, membership-only, неполные, неоднозначные,
cross-version и дублирующиеся доказательства.

### 91.10 — Обновить registry и провести итоговую приёмку

Заменить предположительные semantic labels доказанными связями, обновить
catalog, runtime profiles и acceptance. Итоговый отчёт обязан содержать ровно
408 подтверждённых bindings, ноль unresolved/ambiguous/visual-only записей и
отдельные passing assertions для single/double jump Астерикса.

## Порядок gates

Каждый actor/profile проходит одинаковый цикл:

1. статическая цепочка доказательств;
2. независимая локальная динамическая проверка;
3. запись в evidence dataset;
4. provenance validation;
5. только затем изменение semantic label/runtime binding.

Задача 91 считается выполненной только после gate 91.10. Частично
восстановленные профили остаются в локальном evidence dataset и не позволяют
перенести задачу в completed backlog.
