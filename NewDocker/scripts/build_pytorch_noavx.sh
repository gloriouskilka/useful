#!/usr/bin/env bash
set -Eeuo pipefail

# Конфигурация и сборка PyTorch без AVX/AVX2/AVX512
# Работает в каталоге репозитория PyTorch: /workspace/pytorch

PytorchDir=${1:-/workspace/pytorch}
BuildDir="${PytorchDir}/build"

if [[ ! -d "${PytorchDir}" ]]; then
  echo "[ERR] PyTorch dir not found: ${PytorchDir}" 1>&2
  exit 1
fi

# Python из venv
PYTHON_EXECUTABLE=${PYTHON_EXECUTABLE:-/opt/venv/bin/python}
if [[ ! -x "${PYTHON_EXECUTABLE}" ]]; then
  echo "[WARN] PYTHON_EXECUTABLE not found at ${PYTHON_EXECUTABLE}; using python"
  PYTHON_EXECUTABLE=$(command -v python || echo python)
fi

# site-packages для CMAKE_PREFIX_PATH (можно оставить дефолт)
SITE_PACKAGES=${CMAKE_PREFIX_PATH:-/opt/venv/lib/python3.10/site-packages}

# Пути OpenBLAS по архитектуре
arch=$(uname -m || true)
if [[ "${arch}" == "x86_64" || "${arch}" == "amd64" ]]; then
  OPENBLAS_LIB=/usr/lib/x86_64-linux-gnu/libopenblas.so
else
  OPENBLAS_LIB=/usr/lib/aarch64-linux-gnu/libopenblas.so
fi
OPENBLAS_INC=/usr/include

echo "[pyTorch-noavx] Configure: ${PytorchDir} -> ${BuildDir}"
rm -rf "${BuildDir}"
cmake -S "${PytorchDir}" -B "${BuildDir}" -GNinja \
  -DBUILD_PYTHON=ON -DBUILD_TEST=OFF \
  -DBLAS=OpenBLAS -DOpenBLAS_LIB="${OPENBLAS_LIB}" -DOpenBLAS_INCLUDE_DIR="${OPENBLAS_INC}" \
  -DUSE_MKLDNN=OFF -DUSE_MKL=OFF \
  -DUSE_FBGEMM=OFF -DUSE_QNNPACK=OFF -DUSE_PYTORCH_QNNPACK=OFF -DUSE_XNNPACK=OFF \
  -DATEN_CPU_STATIC_DISPATCH=DEFAULT -DCPU_CAPABILITY=default \
  -DUSE_AVX=OFF -DC_HAS_AVX_2=OFF -DC_HAS_AVX2_2=OFF -DCXX_HAS_AVX_2=OFF -DCXX_HAS_AVX2_2=OFF \
  -DCAFFE2_COMPILER_SUPPORTS_AVX512_EXTENSIONS=OFF \
  -DUSE_SYSTEM_PROTOBUF=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DPYTHON_EXECUTABLE="${PYTHON_EXECUTABLE}" \
  -DCMAKE_PREFIX_PATH="${SITE_PACKAGES}" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5

echo "[pyTorch-noavx] Build"
cmake --build "${BuildDir}" -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

echo "[pyTorch-noavx] Done. To install into venv run:"
echo "  (cd ${PytorchDir} && ${PYTHON_EXECUTABLE} setup.py develop)"


