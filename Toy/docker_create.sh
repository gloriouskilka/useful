#!/usr/bin/env bash
set -Eeuo pipefail

IMAGE_NAME="toy-dev"
CONTAINER_NAME="toy-dev"
WORKSPACE_IN_CONTAINER="/workspaces/Toy"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"

RECREATE=false
RUN_TESTS=false
CLEAR_VENV=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--recreate] [--run-tests] [--clear] [--help]

  --recreate   Пересобрать образ без кэша и пересоздать контейнер
  --run-tests  После запуска контейнера выполнить postCreate.sh и тесты
  --clear      Пересоздать виртуальное окружение (.venv) внутри контейнера
  --help       Показать эту справку

Примеры:
  $0 --recreate
  $0 --run-tests
  $0 --run-tests --clear
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --recreate)
      RECREATE=true
      shift
      ;;
    --run-tests)
      RUN_TESTS=true
      shift
      ;;
    --clear)
      CLEAR_VENV=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Неизвестный аргумент: $1" >&2
      usage
      exit 1
      ;;
  esac
done

echo "[docker_create] Project root: ${PROJECT_ROOT}"

run_inside_container() {
  echo "[docker_create] Обнаружена среда контейнера. Перехожу в локальный режим (без docker CLI)."
  if ${RECREATE}; then
    echo "[docker_create] Предупреждение: флаг --recreate игнорируется внутри контейнера." >&2
  fi
  if ${RUN_TESTS}; then
    echo "[docker_create] Выполняю .devcontainer/postCreate.sh и тесты внутри контейнера"
    if ${CLEAR_VENV}; then
      UV_VENV_CLEAR=1 bash .devcontainer/postCreate.sh
    else
      bash .devcontainer/postCreate.sh
    fi
    source .venv/bin/activate && python mydev/python/dev.py && python mydev/python/test_mydev.py
  else
    echo "[docker_create] Внутри контейнера можно запустить:"
    if ${CLEAR_VENV}; then
      echo "  UV_VENV_CLEAR=1 bash .devcontainer/postCreate.sh"
    else
      echo "  bash .devcontainer/postCreate.sh"
    fi
    echo "  source .venv/bin/activate && python mydev/python/dev.py && python mydev/python/test_mydev.py"
  fi
  exit 0
}

# Если скрипт запущен внутри контейнера — выполняем локальные шаги
if [ -f "/.dockerenv" ] || grep -qa "docker\|containerd" /proc/1/cgroup 2>/dev/null; then
  run_inside_container
fi

# Проверка наличия docker CLI
if ! command -v docker >/dev/null 2>&1; then
  echo "[docker_create] Не найден docker CLI. Установите Docker Desktop/Engine и убедитесь, что команда 'docker' доступна." >&2
  exit 1
fi

BUILD_ARGS=(
  -f "${PROJECT_ROOT}/.devcontainer/Dockerfile"
  -t "${IMAGE_NAME}"
  --build-arg "USERNAME=vscode"
  --build-arg "USER_UID=$(id -u)"
  --build-arg "USER_GID=$(id -g)"
  --pull
)

if ${RECREATE}; then
  BUILD_ARGS+=(--no-cache)
fi

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "[docker_create] Обнаружен существующий контейнер ${CONTAINER_NAME}"
  if ${RECREATE}; then
    echo "[docker_create] --recreate: останавливаю и удаляю контейнер ${CONTAINER_NAME}"
    docker rm -f "${CONTAINER_NAME}" || true
  else
    echo "[docker_create] Контейнер уже существует. Пропускаю пересоздание."
  fi
fi

echo "[docker_create] Сборка образа ${IMAGE_NAME}"
docker build "${BUILD_ARGS[@]}" "${PROJECT_ROOT}"

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "[docker_create] Запуск существующего контейнера ${CONTAINER_NAME}"
    docker start "${CONTAINER_NAME}" >/dev/null
  else
    echo "[docker_create] Создание и запуск контейнера ${CONTAINER_NAME}"
    docker run -d \
      --name "${CONTAINER_NAME}" \
      --restart unless-stopped \
      -v "${PROJECT_ROOT}:${WORKSPACE_IN_CONTAINER}" \
      -v uv-cache:/home/vscode/.cache/uv \
      -w "${WORKSPACE_IN_CONTAINER}" \
      "${IMAGE_NAME}" \
      sleep infinity >/dev/null
  fi
else
  echo "[docker_create] Контейнер ${CONTAINER_NAME} уже запущен"
fi

echo "[docker_create] Контейнер готов: ${CONTAINER_NAME} (image: ${IMAGE_NAME})"

# Выполняем postCreate и тесты по запросу
if ${RUN_TESTS}; then
  echo "[docker_create] --run-tests: выполняю .devcontainer/postCreate.sh и тесты"
  # Починить права на volume кэша uv (создан root'ом при первом монтировании)
  docker exec -w / -u root "${CONTAINER_NAME}" bash -lc 'mkdir -p /home/vscode/.cache/uv && chown -R vscode:vscode /home/vscode/.cache'
  if ${CLEAR_VENV}; then
    docker exec -e UV_VENV_CLEAR=1 -u vscode -w "${WORKSPACE_IN_CONTAINER}" "${CONTAINER_NAME}" bash -lc 'bash .devcontainer/postCreate.sh'
  else
    docker exec -u vscode -w "${WORKSPACE_IN_CONTAINER}" "${CONTAINER_NAME}" bash -lc 'bash .devcontainer/postCreate.sh'
  fi
  docker exec -u vscode -w "${WORKSPACE_IN_CONTAINER}" "${CONTAINER_NAME}" bash -lc 'source .venv/bin/activate && python mydev/python/dev.py && python mydev/python/test_mydev.py'
fi

cat <<EOM

Готово.

Подключение из VSCode/Cursor:
  - В VSCode установите Docker и Dev Containers расширения
  - Команда: "Dev Containers: Attach to Running Container" → ${CONTAINER_NAME}
  - Рабочая папка внутри контейнера: ${WORKSPACE_IN_CONTAINER}

CLI-доступ:
  docker exec -it -u vscode ${CONTAINER_NAME} bash

Остановка/удаление:
  docker stop ${CONTAINER_NAME}
  docker rm ${CONTAINER_NAME}
EOM


