#!/usr/bin/env bash
set -euo pipefail

echo "[postCreate] Python env via uv + build C++"

# В контейнере работаем в /workspaces/Toy
cd /workspaces/Toy

# 1) Настройка uv и виртуального окружения
if ! command -v uv >/dev/null 2>&1; then
  export PATH="/usr/local/bin:${PATH}"
fi
if ! command -v uv >/dev/null 2>&1; then
  echo "uv не найден — проверьте Dockerfile установку" >&2
  exit 1
fi

# Обеспечить права на кэш uv для пользователя vscode
mkdir -p /home/vscode/.cache/uv || true
chmod 700 /home/vscode/.cache || true
chmod 700 /home/vscode/.cache/uv || true

# Создаем и активируем venv (uv сам управляет)
if [[ "${UV_VENV_CLEAR:-}" == "1" ]]; then
  echo "[postCreate] Clearing existing venv (.venv)"
  rm -rf .venv || true
fi
uv venv --python 3.12
source .venv/bin/activate

# 2) Установка только нужных пакетов для проекта в .venv
uv pip install -p .venv/bin/python --upgrade pip
uv pip install -p .venv/bin/python torch
uv pip install -p .venv/bin/python 'debugpy>=1.8.0'

# 3) Проверка torch и CMake-сборка mydev_backend через CMakePresets py-debug
python - <<'PY'
import torch, sys
print('Torch version:', torch.__version__)
PY

# Сборка C++ для Python-пути (.venv)
pushd mydev >/dev/null
# Умная очистка CMakeCache: если кэш указывает на другую исходную директорию — удаляем билд
BUILD_DIR="../build-py/py-debug"
SRC_DIR="$(pwd)"
if [ -f "${BUILD_DIR}/CMakeCache.txt" ]; then
  cached_src="$(grep -E '^CMAKE_HOME_DIRECTORY(:INTERNAL)?=' "${BUILD_DIR}/CMakeCache.txt" | head -n1 | cut -d= -f2 || true)"
  if [ -n "${cached_src}" ]; then
    if [ "$(realpath -m "${cached_src}")" != "$(realpath -m "${SRC_DIR}")" ]; then
      echo "[postCreate] CMakeCache указывает на другой source (${cached_src}), очищаю ${BUILD_DIR}"
      rm -rf "${BUILD_DIR}"
    fi
  fi
fi

# Конфигурация CMake с авто-очисткой при первой ошибке
if ! cmake --preset py-debug; then
  echo "[postCreate] cmake configure failed — очищаю ${BUILD_DIR} и повторяю"
  rm -rf "${BUILD_DIR}"
  cmake --preset py-debug
fi
cmake --build --preset py-debug -j
popd >/dev/null

echo "[postCreate] Done."


