# Asterix & Obelix XXL macOS runtime

Оригинальные игровые ресурсы не входят в репозиторий. Перед первым запуском
соберите локальный ASTPAK из своей установленной копии игры:

```sh
./scripts/install_slice_assets.sh "/путь/к/AsterixXXL"
```

Скрипт установит пакет в
`~/Library/Application Support/AsterixXXL/gaul-stage-1.astpak`. После этого
`make run` и запуск «Новой игры» находят его автоматически. Если стандартного
пакета нет, приложение предлагает выбрать ранее собранный `.astpak` вручную.

Для локальной установки Triada в текущем окружении команда выглядит так:

```sh
./scripts/install_slice_assets.sh "$HOME/Downloads/Asterix & Obelix XXL (Triada)/prefix/drive_c/AsterixXXL"
```

Сборка требует закреплённый через FVM Flutter SDK. ASTPAK и производные игровые
данные должны оставаться вне Git.
