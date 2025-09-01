#!/usr/bin/env bash
set -Eeuo pipefail

# Образ и контейнер
IMAGE_NAME="ttnn-dev"
CONTAINER_NAME="ttnn-dev"

# Пути
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"
WORKSPACE_IN_CONTAINER="/workspace"

RECREATE=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--recreate] [--help]

  --recreate     Пересобрать образ без кэша и пересоздать контейнер
  --help         Показать справку

Пример:
  $0 --recreate
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --recreate)
      RECREATE=true; shift;;
    
    --help|-h)
      usage; exit 0;;
    *)
      echo "Неизвестный аргумент: $1" >&2
      usage; exit 1;;
  esac
done

echo "[docker_dev] Project root: ${PROJECT_ROOT}"

# Проверка docker
if ! command -v docker >/dev/null 2>&1; then
  echo "[docker_dev] Не найден docker CLI" >&2; exit 1
fi

# Сборка образа
BUILD_ARGS=(
  -f "${PROJECT_ROOT}/Dockerfile"
  -t "${IMAGE_NAME}"
  --pull
)
${RECREATE} && BUILD_ARGS+=(--no-cache)

# Фиксированный путь к tt-metal внутри workspace
echo "[docker_dev] Использую TT_METAL_SRC=pytorch2.0_ttnn/torch_ttnn/cpp_extension/third-party/tt-metal"
BUILD_ARGS+=(--build-arg TT_METAL_SRC=pytorch2.0_ttnn/torch_ttnn/cpp_extension/third-party/tt-metal)

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "[docker_dev] Найден существующий контейнер ${CONTAINER_NAME}"
  ${RECREATE} && { echo "[docker_dev] --recreate: удаляю контейнер"; docker rm -f "${CONTAINER_NAME}" || true; }
fi

echo "[docker_dev] Сборка образа ${IMAGE_NAME}"
docker build "${BUILD_ARGS[@]}" "${PROJECT_ROOT}"

# Подготовка опций запуска (монтирование устройств, если есть)
RUN_OPTS=(
  --name "${CONTAINER_NAME}"
  --restart unless-stopped
  -v "${PROJECT_ROOT}:${WORKSPACE_IN_CONTAINER}"
  -w "${WORKSPACE_IN_CONTAINER}"
)

# Монтирование hugepages и /dev/tenstorrent при наличии
if [[ -d /dev/hugepages-1G ]]; then
  RUN_OPTS+=( -v /dev/hugepages-1G:/dev/hugepages-1G )
fi
if [[ -e /dev/tenstorrent ]]; then
  RUN_OPTS+=( --device /dev/tenstorrent )
fi

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "[docker_dev] Запуск существующего контейнера ${CONTAINER_NAME}"
    docker start "${CONTAINER_NAME}" >/dev/null
  else
    echo "[docker_dev] Создание и запуск контейнера ${CONTAINER_NAME}"
    docker run -d "${RUN_OPTS[@]}" "${IMAGE_NAME}" sleep infinity >/dev/null
  fi
else
  echo "[docker_dev] Контейнер ${CONTAINER_NAME} уже запущен"
fi

echo "[docker_dev] Контейнер готов: ${CONTAINER_NAME} (image: ${IMAGE_NAME})"

:

cat <<EOM

Готово.

Подключение:
  docker exec -it ${CONTAINER_NAME} bash

Остановка/удаление:
  docker stop ${CONTAINER_NAME}
  docker rm ${CONTAINER_NAME}
EOM


