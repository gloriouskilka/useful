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
bash ./do
```

#### Полные dev-зависимости (медленно; может падать на fiftyone-db)

```bash
bash ./docker_dev.sh --post-create --full-dev
```

#### Подключение в контейнер

```bash
docker exec -it ttnn-dev bash
```

#### Ручной запуск сборки тулчейна из workspace

Скрипт сборки находится в `scripts/build_toolchain.sh` и не вшивается в образ. Запустите его внутри контейнера из корня workspace:

```bash
docker exec -it ttnn-dev bash -lc 'NO_AVX_FLAGS="-mno-avx -mno-avx2 -mno-sse4.2 -mno-sse4.1" bash ./scripts/build_toolchain.sh'
```

Можно кастомизировать версии (переменные среды): `BOOST_VERSION`, `PYBIND11_VERSION`, `RANGE_V3_VERSION`, `TAKSFLOW_VERSION`, `XTENSOR_XTL_VERSION`, `DOXYGEN_VERSION`.

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


