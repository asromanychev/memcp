# Storage Directory

## Atlas Mirror (`storage/atlas`)

- `atlas:sync` создаёт зеркало документации из `insales_atlas/`.
- Контент складывается в `storage/atlas/blobs/{sha256}.{ext}` — один blob на уникальный файл; дубликаты переиспользуют существующий SHA.
- `storage/atlas/index.json` содержит метаданные:
  - `source_path` — относительный путь в `insales_atlas`.
  - `sha256`, `blob_path`, `size_bytes`.
  - `duplicate_of` — первая запись с таким же содержимым (если есть).
  - `category` — верхний каталог (features, conventions, etc.).
  - `title` — заголовок (для Markdown) или имя файла.
- Повторный запуск `bundle exec rails atlas:sync` обновляет индекс и докидывает новые файлы, не создавая клонов.

## Local Artifacts

- Здесь могут появляться сгенерированные файлы (blobs, индексы). Они игнорируются git'ом, но нужны приложению в runtime.
- Не храните вручную редактируемые документы в `storage` — источником правды остаётся `insales_atlas`.

