### Docker dev: быстрый старт

- Требования: в корне проекта есть checkout `tt-metal` (ожидается путь `./tt-metal`). Если путь иной — см. ниже раздел про `TT_METAL_SRC`.

#### Собрать и запустить контейнер

```bash
bash ./docker_dev.sh --recreate
```

#### Пост-настройка

Вся последовательность (зависимости tt-metal → сборка PyTorch → сборка tt-metal) выполняется единым скриптом `scripts/build_toolchain.sh`.

```bash
docker exec -it ttnn-dev bash -lc 'NO_AVX_FLAGS="-mno-avx -mno-avx2 -mno-sse4.2 -mno-sse4.1" bash ./scripts/build_toolchain.sh'
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
 
### Проверка исходников и фиксация версий (до сборки)

В контейнере, внутри `/workspace`, убедитесь, что каталоги и версии исходников соответствуют ожидаемым.

1) PyTorch (ожидаемая версия: v2.2.1)

```bash
cd /workspace
test -d pytorch || git clone https://github.com/pytorch/pytorch.git pytorch
cd pytorch
git remote set-url origin https://github.com/pytorch/pytorch.git
git fetch --tags --force --prune
git checkout tags/v2.2.1
git submodule sync --recursive
git submodule update --init --recursive
```

2) pytorch2.0_ttnn (проверено на v0.60.1)

```bash
cd /workspace
test -d pytorch2.0_ttnn || git clone https://github.com/tenstorrent/pytorch2.0_ttnn.git pytorch2.0_ttnn
cd pytorch2.0_ttnn
git remote set-url origin https://github.com/tenstorrent/pytorch2.0_ttnn.git
git fetch --tags --force --prune
git checkout tags/v0.60.1
git submodule sync --recursive
git submodule update --init --recursive
```

После этого запускайте:

```bash
docker exec -it ttnn-dev bash -lc 'source /etc/profile.d/tt_env.sh && ./scripts/build_toolchain.sh --rebuild'
docker exec -it ttnn-dev bash -lc 'source /etc/profile.d/tt_env.sh && ./scripts/build_ttnn_cpp_extension.sh --rebuild'
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

Пост-настройка запускается вручную через `scripts/build_toolchain.sh` (см. выше).

### Примечания

- Скрипт автоматически примонтирует `/dev/hugepages-1G` и устройство `/dev/tenstorrent`, если они доступны на хосте.
- `--full-dev` пробрасывает `FULL_DEV_REQS=1` во встроенную пост-настройку и устанавливает тяжёлые dev-зависимости tt-metal.


