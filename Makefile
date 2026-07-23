SHELL := /bin/zsh

FVM := fvm
FLUTTER := $(FVM) flutter
DART := $(FVM) dart

.DEFAULT_GOAL := help

.PHONY: help setup get inventory task91-corpus task91-headless task91-anchors task91-primitives task91-dispatch task91-asterix-profile task91-controlled-heroes-profile task91-enemies-scripted-profile task91-world-cinematics-profile task91-provenance-gate task91-final-acceptance task91-tooling-test task92-release-audit task93-asterix-behaviour task93-authored-graph task93-remaining-graphs task93-behavioural-pose-accept task93-release-gate task93-tooling-test importer-inspect animation-catalog-validate animation-catalog-accept animation-bindings-accept animation-dictionary-validate animation-dictionaries-validate animation-character-annotations animation-character-graph animation-characters-validate animation-world-annotations animation-world-graph animation-world-validate animation-cinematic-annotations animation-cinematic-graph animation-cinematics-validate animation-review package-inspect visual-regression run run-profile run-release format analyze test native-test ffi-generate native-ffi-build policy-check check build clean doctor

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

task91-corpus: ## Зафиксировать PE/KWN corpus задачи 91 (GAME_DIR=... OUTPUT=...)
	@test -n "$(GAME_DIR)" -a -n "$(OUTPUT)" || (echo 'Укажите GAME_DIR=... OUTPUT=...' >&2; exit 2)
	python3 scripts/task91_corpus.py "$(GAME_DIR)" "$(OUTPUT)"

task91-headless: ## Чистый headless-анализ задачи 91 (GAME_DIR=... WORKSPACE=...)
	@test -n "$(GAME_DIR)" -a -n "$(WORKSPACE)" || (echo 'Укажите GAME_DIR=... WORKSPACE=...' >&2; exit 2)
	./scripts/task91_headless_analysis.sh "$(GAME_DIR)" "$(WORKSPACE)"

task91-anchors: ## Карта class/function anchors (GAME_DIR=... XXL_EDITOR=... OUTPUT=...)
	@test -n "$(GAME_DIR)" -a -n "$(XXL_EDITOR)" -a -n "$(OUTPUT)" || (echo 'Укажите GAME_DIR=... XXL_EDITOR=... OUTPUT=...' >&2; exit 2)
	python3 scripts/task91_class_anchors.py "$(GAME_DIR)" "$(XXL_EDITOR)" "$(OUTPUT)"

task91-primitives: ## Call graph animation primitives (GAME_DIR=... ANCHORS=... OUTPUT=...)
	@test -n "$(GAME_DIR)" -a -n "$(ANCHORS)" -a -n "$(OUTPUT)" || (echo 'Укажите GAME_DIR=... ANCHORS=... OUTPUT=...' >&2; exit 2)
	python3 scripts/task91_animation_primitives.py "$(GAME_DIR)" "$(ANCHORS)" "$(OUTPUT)"

task91-dispatch: ## Numeric state/event dispatch (GAME_DIR=... ANCHORS=... PRIMITIVES=... OUTPUT=...)
	@test -n "$(GAME_DIR)" -a -n "$(ANCHORS)" -a -n "$(PRIMITIVES)" -a -n "$(OUTPUT)" || (echo 'Укажите GAME_DIR=... ANCHORS=... PRIMITIVES=... OUTPUT=...' >&2; exit 2)
	python3 scripts/task91_numeric_dispatch.py "$(GAME_DIR)" "$(ANCHORS)" "$(PRIMITIVES)" "$(OUTPUT)"

task91-asterix-profile: ## Authored profile Астерикса (GAME_DIR=... ANCHORS=... DISPATCH=... OUTPUT=...)
	@test -n "$(GAME_DIR)" -a -n "$(ANCHORS)" -a -n "$(DISPATCH)" -a -n "$(OUTPUT)" || (echo 'Укажите GAME_DIR=... ANCHORS=... DISPATCH=... OUTPUT=...' >&2; exit 2)
	python3 scripts/task91_asterix_profile.py "$(GAME_DIR)" "$(ANCHORS)" "$(DISPATCH)" assets/animation_bindings.v1.json "$(OUTPUT)"

task91-controlled-heroes-profile: ## Authored profiles Обеликса и Идефикса (GAME_DIR=... ANCHORS=... DISPATCH=... OUTPUT=...)
	@test -n "$(GAME_DIR)" -a -n "$(ANCHORS)" -a -n "$(DISPATCH)" -a -n "$(OUTPUT)" || (echo 'Укажите GAME_DIR=... ANCHORS=... DISPATCH=... OUTPUT=...' >&2; exit 2)
	python3 scripts/task91_controlled_heroes_profile.py "$(GAME_DIR)" "$(ANCHORS)" "$(DISPATCH)" assets/animation_bindings.v1.json "$(OUTPUT)"

task91-enemies-scripted-profile: ## Authored profiles enemies и scripted actors (GAME_DIR=... ANCHORS=... DISPATCH=... OUTPUT=...)
	@test -n "$(GAME_DIR)" -a -n "$(ANCHORS)" -a -n "$(DISPATCH)" -a -n "$(OUTPUT)" || (echo 'Укажите GAME_DIR=... ANCHORS=... DISPATCH=... OUTPUT=...' >&2; exit 2)
	python3 scripts/task91_enemies_scripted_profile.py "$(GAME_DIR)" "$(ANCHORS)" "$(DISPATCH)" assets/animation_bindings.v1.json "$(OUTPUT)"

task91-world-cinematics-profile: ## Authored profiles world/UI/FX и cinematics (GAME_DIR=... ANCHORS=... DISPATCH=... OUTPUT=...)
	@test -n "$(GAME_DIR)" -a -n "$(ANCHORS)" -a -n "$(DISPATCH)" -a -n "$(OUTPUT)" || (echo 'Укажите GAME_DIR=... ANCHORS=... DISPATCH=... OUTPUT=...' >&2; exit 2)
	python3 scripts/task91_world_cinematics_profile.py "$(GAME_DIR)" "$(ANCHORS)" "$(DISPATCH)" assets/animation_bindings.v1.json "$(OUTPUT)"

task91-provenance-gate: ## Строгий provenance gate всех 408 bindings (ASTERIX=... CONTROLLED_HEROES=... ENEMIES_SCRIPTED=... WORLD_CINEMATICS=... OUTPUT=...)
	@test -n "$(ASTERIX)" -a -n "$(CONTROLLED_HEROES)" -a -n "$(ENEMIES_SCRIPTED)" -a -n "$(WORLD_CINEMATICS)" -a -n "$(OUTPUT)" || (echo 'Укажите ASTERIX=... CONTROLLED_HEROES=... ENEMIES_SCRIPTED=... WORLD_CINEMATICS=... OUTPUT=...' >&2; exit 2)
	python3 scripts/task91_provenance_gate.py "$(ASTERIX)" "$(CONTROLLED_HEROES)" "$(ENEMIES_SCRIPTED)" "$(WORLD_CINEMATICS)" assets/animation_bindings.v1.json "$(OUTPUT)"

task91-final-acceptance: ## Обновить локальные catalog/registry и принять 408 bindings (CATALOG=... PROVENANCE=... OUTPUT_DIR=...)
	@test -n "$(CATALOG)" -a -n "$(PROVENANCE)" -a -n "$(OUTPUT_DIR)" || (echo 'Укажите CATALOG=... PROVENANCE=... OUTPUT_DIR=...' >&2; exit 2)
	python3 scripts/task91_final_acceptance.py "$(CATALOG)" assets/animation_bindings.v1.json "$(PROVENANCE)" "$(OUTPUT_DIR)/animation-catalog.task91.json" "$(OUTPUT_DIR)/animation-bindings.task91.json" "$(OUTPUT_DIR)/acceptance.task91.json"

task91-tooling-test: ## Проверить metadata-only tooling задачи 91
	python3 -m unittest test/task91_corpus_test.py
	python3 -m unittest test/task91_class_anchors_test.py
	python3 -m unittest test/task91_animation_primitives_test.py
	python3 -m unittest test/task91_numeric_dispatch_test.py
	python3 -m unittest test/task91_asterix_profile_test.py
	python3 -m unittest test/task91_controlled_heroes_profile_test.py
	python3 -m unittest test/task91_enemies_scripted_profile_test.py
	python3 -m unittest test/task91_world_cinematics_profile_test.py
	python3 -m unittest test/task91_provenance_gate_test.py
	python3 -m unittest test/task91_final_acceptance_test.py
	bash -n scripts/task91_headless_analysis.sh

task93-asterix-behaviour: ## Behavioural provenance Астерикса (GAME_DIR=... PROFILE=... OUTPUT=...)
	@test -n "$(GAME_DIR)" || (echo "GAME_DIR is required" >&2; exit 2)
	@test -n "$(PROFILE)" || (echo "PROFILE is required" >&2; exit 2)
	@test -n "$(OUTPUT)" || (echo "OUTPUT is required" >&2; exit 2)
	python3 scripts/task93_asterix_behaviour.py "$(GAME_DIR)" "$(PROFILE)" "$(OUTPUT)"

task93-authored-graph: ## Собрать runtime graph из принятого provenance (PROVENANCE=... OUTPUT=... CACHE_DIR=...)
	@test -n "$(PROVENANCE)" || (echo "PROVENANCE is required" >&2; exit 2)
	@test -n "$(OUTPUT)" || (echo "OUTPUT is required" >&2; exit 2)
	python3 scripts/task93_authored_animation_graph.py "$(PROVENANCE)" "$(OUTPUT)" $(if $(CACHE_DIR),--cache-dir "$(CACHE_DIR)",)

task93-remaining-graphs: ## Собрать controller/timeline graph остальных 318 bindings (OUTPUT=...)
	@test -n "$(OUTPUT)" || (echo "OUTPUT is required" >&2; exit 2)
	python3 scripts/task93_remaining_animation_graphs.py assets/animation_bindings.v1.json "$(OUTPUT)"

task93-behavioural-pose-accept: ## Сверить локальные traces оригинала и runtime (REFERENCE_DIR=... CANDIDATE_DIR=... OUTPUT=...)
	@test -n "$(REFERENCE_DIR)" || (echo "REFERENCE_DIR is required" >&2; exit 2)
	@test -n "$(CANDIDATE_DIR)" || (echo "CANDIDATE_DIR is required" >&2; exit 2)
	@test -n "$(OUTPUT)" || (echo "OUTPUT is required" >&2; exit 2)
	python3 scripts/task93_behavioural_pose_acceptance.py tools/task93/behavioural_pose_acceptance.v1.json "$(REFERENCE_DIR)" "$(CANDIDATE_DIR)" "$(OUTPUT)"

task93-release-gate: ## Animation fidelity gate fresh/cached/installed ASTPAK и runtime evidence
	@test -n "$(FRESH)" -a -n "$(CACHED)" -a -n "$(INSTALLED)" -a -n "$(REGISTRY)" -a -n "$(ACCEPTANCE)" -a -n "$(RUNTIME_EVIDENCE)" || (echo 'Укажите FRESH=... CACHED=... INSTALLED=... REGISTRY=... ACCEPTANCE=... RUNTIME_EVIDENCE=...' >&2; exit 2)
	$(DART) run bin/task93_release_gate.dart "$(FRESH)" "$(CACHED)" "$(INSTALLED)" "$(REGISTRY)" "$(ACCEPTANCE)" assets/animation_graphs/asterix.authored-graph.v1.json assets/animation_graphs/actors.authored-graphs.v1.json "$(RUNTIME_EVIDENCE)"

task93-tooling-test: ## Проверить metadata-only tooling задач 93.1–93.2 и 93.6–93.8
	python3 -m unittest test/task93_asterix_behaviour_test.py
	python3 -m unittest test/task93_authored_animation_graph_test.py
	python3 -m unittest test/task93_behavioural_pose_acceptance_test.py
	python3 -m unittest test/task93_remaining_animation_graphs_test.py
	$(FLUTTER) test test/animation_fidelity_release_gate_test.dart

task92-release-audit: ## Проверить ASTPAK против принятого registry п. 91.10 (INPUT=... REGISTRY=... ACCEPTANCE=...)
	@test -n "$(INPUT)" -a -n "$(REGISTRY)" -a -n "$(ACCEPTANCE)" || (echo 'Укажите INPUT=... REGISTRY=... ACCEPTANCE=...' >&2; exit 2)
	$(DART) run bin/task92_release_audit.dart "$(INPUT)" "$(REGISTRY)" "$(ACCEPTANCE)"

importer-inspect: ## Проверить файл каркасом импортёра (INPUT=...)
	@test -n "$(INPUT)" || (echo 'Укажите INPUT=/путь/к/файлу' >&2; exit 2)
	$(DART) run bin/importer.dart inspect "$(INPUT)"

animation-catalog-validate: ## Проверить полный семантический каталог (INPUT=...)
	@test -n "$(INPUT)" || (echo 'Укажите INPUT=/путь/к/catalog.json' >&2; exit 2)
	$(DART) run bin/animation_catalog.dart validate "$(INPUT)"

animation-catalog-accept: ## Финальная приёмка каталога LVL01: 345 clips / 518 slots (INPUT=...)
	@test -n "$(INPUT)" || (echo 'Укажите INPUT=/путь/к/catalog.json' >&2; exit 2)
	$(DART) run bin/animation_catalog.dart accept-lvl01 "$(INPUT)"

animation-bindings-accept: ## Сквозная приёмка catalog → bindings → runtime paths (CATALOG=... OUTPUT=...)
	@test -n "$(CATALOG)" -a -n "$(OUTPUT)" || (echo 'Укажите CATALOG=... OUTPUT=...' >&2; exit 2)
	$(DART) run bin/animation_binding_acceptance.dart "$(CATALOG)" assets/animation_bindings.v1.json assets/animation_visual_acceptance.v1.json "$(OUTPUT)"

animation-dictionary-validate: ## Проверить один словарь (DICTIONARY=... INPUT=...)
	@test -n "$(DICTIONARY)" -a -n "$(INPUT)" || (echo 'Укажите DICTIONARY=... INPUT=...' >&2; exit 2)
	$(DART) run bin/animation_catalog.dart validate-dictionary "$(DICTIONARY)" "$(INPUT)"

animation-dictionaries-validate: ## Проверить набор словарей (DICTIONARIES=0,1 INPUT=...)
	@test -n "$(DICTIONARIES)" -a -n "$(INPUT)" || (echo 'Укажите DICTIONARIES=0,1 INPUT=...' >&2; exit 2)
	$(DART) run bin/animation_catalog.dart validate-dictionaries "$(DICTIONARIES)" "$(INPUT)"

animation-characters-validate: ## Проверить все character dictionaries (INPUT=...)
	@test -n "$(INPUT)" || (echo 'Укажите INPUT=/путь/к/catalog.json' >&2; exit 2)
	$(DART) run bin/animation_catalog.dart validate-character-dictionaries "$(INPUT)"

animation-character-annotations: ## Построить character-аннотации (INPUT=... OUTPUT=...)
	@test -n "$(INPUT)" -a -n "$(OUTPUT)" || (echo 'Укажите INPUT=... OUTPUT=...' >&2; exit 2)
	$(DART) run bin/animation_character_annotations.dart "$(INPUT)" "$(OUTPUT)"

animation-character-graph: ## Добавить character graphs в bindings (BINDINGS=... ANNOTATIONS=... CATALOG=... OUTPUT=...)
	@test -n "$(BINDINGS)" -a -n "$(ANNOTATIONS)" -a -n "$(CATALOG)" -a -n "$(OUTPUT)" || (echo 'Укажите BINDINGS=... ANNOTATIONS=... CATALOG=... OUTPUT=...' >&2; exit 2)
	$(DART) run bin/animation_character_graph.dart "$(BINDINGS)" "$(ANNOTATIONS)" "$(CATALOG)" "$(OUTPUT)"

animation-world-annotations: ## Построить world/UI/FX-аннотации (INPUT=... OUTPUT=...)
	@test -n "$(INPUT)" -a -n "$(OUTPUT)" || (echo 'Укажите INPUT=... OUTPUT=...' >&2; exit 2)
	$(DART) run bin/animation_world_annotations.dart "$(INPUT)" "$(OUTPUT)"

animation-world-graph: ## Добавить world graphs в bindings (BINDINGS=... ANNOTATIONS=... CATALOG=... OUTPUT=...)
	@test -n "$(BINDINGS)" -a -n "$(ANNOTATIONS)" -a -n "$(CATALOG)" -a -n "$(OUTPUT)" || (echo 'Укажите BINDINGS=... ANNOTATIONS=... CATALOG=... OUTPUT=...' >&2; exit 2)
	$(DART) run bin/animation_world_graph.dart "$(BINDINGS)" "$(ANNOTATIONS)" "$(CATALOG)" "$(OUTPUT)"

animation-world-validate: ## Проверить все world/UI/FX dictionaries (INPUT=...)
	@test -n "$(INPUT)" || (echo 'Укажите INPUT=/путь/к/catalog.json' >&2; exit 2)
	$(DART) run bin/animation_catalog.dart validate-world-dictionaries "$(INPUT)"

animation-cinematic-annotations: ## Построить cinematic-аннотации (INPUT=... OUTPUT=...)
	@test -n "$(INPUT)" -a -n "$(OUTPUT)" || (echo 'Укажите INPUT=... OUTPUT=...' >&2; exit 2)
	$(DART) run bin/animation_cinematic_annotations.dart "$(INPUT)" "$(OUTPUT)"

animation-cinematic-graph: ## Добавить scripted/cinematic timelines (BINDINGS=... ANNOTATIONS=... CATALOG=... OUTPUT=...)
	@test -n "$(BINDINGS)" -a -n "$(ANNOTATIONS)" -a -n "$(CATALOG)" -a -n "$(OUTPUT)" || (echo 'Укажите BINDINGS=... ANNOTATIONS=... CATALOG=... OUTPUT=...' >&2; exit 2)
	$(DART) run bin/animation_cinematic_graph.dart "$(BINDINGS)" "$(ANNOTATIONS)" "$(CATALOG)" "$(OUTPUT)"

animation-cinematics-validate: ## Проверить все cinematic dictionaries (INPUT=...)
	@test -n "$(INPUT)" || (echo 'Укажите INPUT=/путь/к/catalog.json' >&2; exit 2)
	$(DART) run bin/animation_catalog.dart validate-cinematic-dictionaries "$(INPUT)"

animation-review: ## Создать HTML для просмотра clips (CATALOG=... ANIMATIONS=... OUTPUT=...)
	@test -n "$(CATALOG)" -a -n "$(ANIMATIONS)" -a -n "$(OUTPUT)" || (echo 'Укажите CATALOG=... ANIMATIONS=... OUTPUT=...' >&2; exit 2)
	$(DART) run bin/animation_review.dart "$(CATALOG)" "$(ANIMATIONS)" "$(OUTPUT)"

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

check: policy-check task91-tooling-test task93-tooling-test native-ffi-build format analyze test ## Выполнить все проверки

build: ## Собрать release-приложение для macOS
	$(FLUTTER) build macos --release

clean: ## Очистить результаты Flutter-сборки
	$(FLUTTER) clean

doctor: ## Проверить окружение Flutter
	$(FLUTTER) doctor -v
