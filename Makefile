SHELL := /bin/zsh

FVM := fvm
FLUTTER := $(FVM) flutter
DART := $(FVM) dart

.DEFAULT_GOAL := help

.PHONY: help setup get inventory importer-inspect package-inspect visual-regression run run-profile run-release format analyze test native-test ffi-generate native-ffi-build policy-check check build clean doctor

help: ## Показать доступные команды
	@awk 'BEGIN {FS = ":.*## "; printf "Команды:\n"} /^[a-zA-Z_-]+:.*## / {printf "  %-14s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: ## Подключить закреплённый Flutter SDK и установить зависимости
	$(FVM) install
	$(FVM) use 3.35.7 --force
	$(MAKE) get

get: ## Установить Flutter-зависимости
	$(FLUTTER) pub get

inventory: ## Построить локальный JSON-манифест оригинальных файлов (GAME_DIR=... OUTPUT=...)
	@test -n "$(GAME_DIR)" || (echo 'Укажите GAME_DIR=/путь/к/AsterixXXL' >&2; exit 2)
	$(DART) run bin/inventory.dart "$(GAME_DIR)" $(if $(OUTPUT),--output "$(OUTPUT)",)

importer-inspect: ## Проверить файл каркасом импортёра (INPUT=...)
	@test -n "$(INPUT)" || (echo 'Укажите INPUT=/путь/к/файлу' >&2; exit 2)
	$(DART) run bin/importer.dart inspect "$(INPUT)"

package-inspect: ## Проверить и вывести manifest runtime-пакета (INPUT=...)
	@test -n "$(INPUT)" || (echo 'Укажите INPUT=/путь/к/package.astpak' >&2; exit 2)
	$(DART) run bin/asset_package.dart inspect "$(INPUT)"

visual-regression: ## Сверить стартовый кадр Gaul (REFERENCE=... ACTUAL=...)
	@test -n "$(REFERENCE)" -a -n "$(ACTUAL)" || (echo 'Укажите REFERENCE=/путь/reference.png ACTUAL=/путь/actual.png' >&2; exit 2)
	$(DART) run bin/gaul_visual_regression.dart "$(REFERENCE)" "$(ACTUAL)"

run: ## Запустить приложение на macOS в debug
	$(FLUTTER) run -d macos

run-profile: ## Запустить приложение на macOS в profile
	$(FLUTTER) run -d macos --profile $(if $(ASSET_PACKAGE),--dart-define=ASTERIX_ASSET_PACKAGE=$(ASSET_PACKAGE),)

run-release: ## Запустить приложение на macOS в release
	$(FLUTTER) run -d macos --release

format: ## Отформатировать Dart-код
	$(DART) format bin lib test

analyze: ## Запустить статический анализ
	$(FLUTTER) analyze

test: ## Запустить тесты
	$(FLUTTER) test

native-test: ## Собрать нативное ядро и запустить его XCTest без Flutter host
	xcodebuild test -workspace macos/Runner.xcworkspace -scheme AsterixEngine -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

ffi-generate: ## Перегенерировать Dart bindings из публичного C header
	$(DART) run ffigen --config ffigen.yaml

native-ffi-build: ## Собрать тестовую dylib из того же C++ runtime для Dart integration-теста
	./scripts/build_native_ffi_test.sh

policy-check: ## Проверить отсутствие оригинальных игровых данных
	./scripts/check_resource_policy.sh

check: policy-check native-ffi-build format analyze test ## Выполнить все проверки

build: ## Собрать release-приложение для macOS
	$(FLUTTER) build macos --release

clean: ## Очистить результаты Flutter-сборки
	$(FLUTTER) clean

doctor: ## Проверить окружение Flutter
	$(FLUTTER) doctor -v
