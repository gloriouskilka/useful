### Docker dev: быстрый старт

- Требования: в корне проекта есть checkout `tt-metal` (ожидается путь `./tt-metal`). Если путь иной — см. ниже раздел про `TT_METAL_SRC`.

#### Собрать и запустить контейнер

```bash
bash ./docker_dev.sh --recreate
```

#### Выполнить пост-настройку (сборка tt-metal, установка pytorch2.0_ttnn)

```bash
bash ./docker_dev.sh --post-create
```

Можно совместить:

```bash
bash ./docker_dev.sh --recreate --post-create
```

#### Полные dev-зависимости (медленно; может падать на fiftyone-db)

```bash
bash ./docker_dev.sh --post-create --full-dev
```

#### Подключение в контейнер

```bash
docker exec -it ttnn-dev bash
```

#### Остановка и удаление контейнера

```bash
docker stop ttnn-dev
docker rm ttnn-dev
```

### Альтернативная сборка с кастомным путём к tt-metal

По умолчанию `Dockerfile` ожидает исходники tt-metal в `./tt-metal`. Если они лежат в другом месте относительно контекста сборки, передайте `--build-arg TT_METAL_SRC=...`:

```bash
docker build -f ./Dockerfile \
  --build-arg TT_METAL_SRC=relative/path/to/tt-metal \
  -t ttnn-dev .

docker run -d --name ttnn-dev \
  --restart unless-stopped \
  -v "$(pwd):/workspace" -w /workspace \
  ttnn-dev sleep infinity
```

После запуска можно выполнить пост-настройку внутри контейнера:

```bash
docker exec ttnn-dev bash -lc 'bash ./postCreate.sh'
```

### Примечания

- Скрипт автоматически примонтирует `/dev/hugepages-1G` и устройство `/dev/tenstorrent`, если они доступны на хосте.
- `--full-dev` пробрасывает `FULL_DEV_REQS=1` в `postCreate.sh` и устанавливает тяжёлые dev-зависимости tt-metal.


