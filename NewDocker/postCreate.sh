#!/usr/bin/env bash
set -Eeuo pipefail

# Скрипт выполняется внутри контейнера. Повторяет шаги сборки tt-metal из исходников
# и устанавливает pytorch2.0_ttnn в editable режиме.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pushd "${ROOT_DIR}" >/dev/null

export DEBIAN_FRONTEND=noninteractive

echo "[postCreate] Проверяю наличие install_dependencies.sh из tt-metal"
TT_METAL_DIR="${ROOT_DIR}/pytorch2.0_ttnn/torch_ttnn/cpp_extension/third-party/tt-metal"
if [[ ! -f "${TT_METAL_DIR}/install_dependencies.sh" ]]; then
  echo "[postCreate] ERROR: не найден ${TT_METAL_DIR}/install_dependencies.sh" >&2
  exit 1
fi

echo "[postCreate] Установка системных зависимостей (runtime/build) через install_dependencies.sh"
sudo /bin/bash "${TT_METAL_DIR}/install_dependencies.sh" --docker --mode build

echo "[postCreate] Активирую виртуальное окружение"
# Предпочитаем venv из базового образа tt-metal (/opt/venv), иначе создаём локальное
if [[ -x "/opt/venv/bin/activate" ]]; then
  source /opt/venv/bin/activate
  echo "[postCreate] Использую venv из базового образа: /opt/venv"
else
  export PYTHON_ENV_DIR="${TT_METAL_DIR}/python_env"
  python3 -m venv "${PYTHON_ENV_DIR}"
  source "${PYTHON_ENV_DIR}/bin/activate"
  echo "[postCreate] Создал локальное venv: ${PYTHON_ENV_DIR}"
fi

echo "[postCreate] Устанавливаю базовые python-инструменты"
python -m pip config set global.extra-index-url https://download.pytorch.org/whl/cpu || true
python -m pip install --upgrade pip setuptools wheel build numpy

# По умолчанию пропускаем тяжёлые dev-зависимости (включая fiftyone-db),
# которые часто ломают установку. Включить можно, задав FULL_DEV_REQS=1
if [[ "${FULL_DEV_REQS:-0}" == "1" ]]; then
  echo "[postCreate] FULL_DEV_REQS=1: Устанавливаю tt-metal dev зависимости"
  python -m pip install -r "${TT_METAL_DIR}/tt_metal/python_env/requirements-dev.txt"
else
  echo "[postCreate] FULL_DEV_REQS!=1: Пропускаю установку tt-metal dev зависимостей"
fi

echo "[postCreate] Собираю tt-metal (как в build_metal.sh по умолчанию Release)"
pushd "${TT_METAL_DIR}" >/dev/null
bash ./build_metal.sh --build-type Release
popd >/dev/null

echo "[postCreate] Устанавливаю pytorch2.0_ttnn в editable режиме"
pushd "${ROOT_DIR}/pytorch2.0_ttnn" >/dev/null
python -m pip install -e .
popd >/dev/null

echo "[postCreate] Готово"
popd >/dev/null


