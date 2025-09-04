#!/usr/bin/env bash
set -Eeuo pipefail

# Use clang-17 by default for ABI compatibility
: "${CC:=clang-17}"; export CC
: "${CXX:=clang++-17}"; export CXX

echo "[ttnn-cpp-ext] CC='${CC}', CXX='${CXX}'"

# Args
REBUILD=0
usage() {
  cat <<EOF
Usage: $(basename "$0") [--rebuild] [--help]

  --rebuild   Очистить промежуточные артефакты перед сборкой
  --help      Показать помощь
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild)
      REBUILD=1; shift;;
    --help|-h)
      usage; exit 0;;
    *)
      echo "Unknown arg: $1" >&2; usage; exit 1;;
  esac
done

# Activate venv
if [[ -x "/opt/venv/bin/activate" ]]; then
  # shellcheck disable=SC1091
  source /opt/venv/bin/activate
  echo "[ttnn-cpp-ext] Using venv: /opt/venv"
fi

workspace_dir="$(pwd)"
repo_dir="${workspace_dir}/pytorch2.0_ttnn"
if [[ ! -d "${repo_dir}" ]]; then
  echo "[ttnn-cpp-ext][ERROR] Repo pytorch2.0_ttnn not found at ${repo_dir}" >&2
  exit 1
fi

ext_dir="${repo_dir}/torch_ttnn/cpp_extension"

# Idempotent patches for pytorch2.0_ttnn/setup.py:
# - remove '+cpu' suffixes
# - relax strict pins 'torch==2.2.1' -> 'torch>=2.2', 'torchvision==0.17.1' -> 'torchvision>=0.17'
patch_torch_deps() {
  local setup_py="${repo_dir}/setup.py"
  if [[ ! -f "${setup_py}" ]]; then
    echo "[ttnn-cpp-ext][patch] ${setup_py} not found, skipping"
    return 0
  fi
  # Remove +cpu tags
  if grep -qE '\+cpu' "${setup_py}"; then
    echo "[ttnn-cpp-ext][patch] Removing '+cpu' tags in ${setup_py}"
    sed -i 's/+cpu//g' "${setup_py}" || true
  fi
  # Relax pins for torch/torchvision
  if grep -q 'torch==2.2.1' "${setup_py}"; then
    echo "[ttnn-cpp-ext][patch] Relaxing torch pin to '>=2.2' in ${setup_py}"
    sed -i 's/torch==2.2.1/torch>=2.2/g' "${setup_py}" || true
  fi
  if grep -q 'torchvision==0.17.1' "${setup_py}"; then
    echo "[ttnn-cpp-ext][patch] Relaxing torchvision pin to '>=0.17' in ${setup_py}"
    sed -i 's/torchvision==0.17.1/torchvision>=0.17/g' "${setup_py}" || true
  fi
}

install_local_ttnn() {
  local ws_ttnn_dir="${repo_dir}/ttnn"
  # Decide if current ttnn is acceptable (must be from workspace)
  python - <<PY || true
import sys, importlib.util, os
spec = importlib.util.find_spec('ttnn')
if spec and spec.origin:
    path = spec.origin
    print(f"[ttnn-cpp-ext] ttnn found at: {path}")
    if '/workspace/pytorch2.0_ttnn/ttnn' not in path:
        sys.exit(2)  # wrong location -> reinstall
    else:
        sys.exit(0)  # correct
else:
    sys.exit(1)  # not importable
PY
  rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "[ttnn-cpp-ext] ttnn from workspace already active"
    return 0
  fi
  echo "[ttnn-cpp-ext] Forcing local ttnn install (rc=$rc)"
  python -m pip uninstall -y ttnn || true
  python3 -m pip uninstall -y ttnn || true
  if [[ -d "${ws_ttnn_dir}" ]]; then
    pushd "${ws_ttnn_dir}" >/dev/null
    python -m pip install -e . --no-build-isolation || true
    python3 -m pip install -e . --no-build-isolation || true
    popd >/dev/null
  else
    echo "[ttnn-cpp-ext][WARN] ${ws_tnn_dir} not found; cannot install local ttnn"
  fi
}

if [[ ${REBUILD} -eq 1 ]]; then
  echo "[ttnn-cpp-ext] --rebuild: cleaning intermediate artifacts in ${ext_dir}"
  rm -rf "${ext_dir}/build" \
         "${ext_dir}"/temp.* \
         "${ext_dir}"/lib.* \
         "${ext_dir}/torch_ttnn_cpp_extension.egg-info" \
         "${ext_dir}/.pytest_cache" \
         "${ext_dir}/CMakeFiles" \
         "${ext_dir}/CMakeCache.txt" || true
  # Не удаляем артефакты tt-metal под submodule: они требуются CMake'ом как prebuilt
  find "${ext_dir}" -name "*.so" -type f \
       -not -path "${ext_dir}/third-party/tt-metal/*" \
       -delete || true
fi

# Resolve TT_METAL_HOME
resolve_tt_metal_home() {
  local tt_metal
  tt_metal="${repo_dir}/torch_ttnn/cpp_extension/third-party/tt-metal"
  if [[ -d "${tt_metal}" ]]; then echo "${tt_metal}"; return 0; fi
  tt_metal="${workspace_dir}/tt-metal"
  if [[ -d "${tt_metal}" ]]; then echo "${tt_metal}"; return 0; fi
  return 1
}

if [[ -z "${TT_METAL_HOME:-}" ]]; then
  if ! TT_METAL_HOME="$(resolve_tt_metal_home)"; then
    echo "[ttnn-cpp-ext][ERROR] TT_METAL_HOME could not be resolved. Expected submodule or ./tt-metal" >&2
    exit 1
  fi
  export TT_METAL_HOME
fi
echo "[ttnn-cpp-ext] TT_METAL_HOME='${TT_METAL_HOME}'"

# Ensure clean/relaxed pins before building/installing python package
patch_torch_deps
install_local_ttnn

# Ensure numpy<2 for many-build compatibility
python - <<'PY'
import sys
import pkgutil
def has_mod(name):
    return pkgutil.find_loader(name) is not None
try:
    import numpy as np
    from packaging.version import Version
    if Version(np.__version__) >= Version("2.0.0"):
        sys.exit(2)
except Exception:
    sys.exit(1)
sys.exit(0)
PY
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "[ttnn-cpp-ext] Installing compatible numpy and build deps"
  python -m pip install --upgrade "numpy<2" setuptools wheel
fi

set -x
pushd "${ext_dir}" >/dev/null
# Ensure submodules are ready (when using the submodule path)
# TODO: should be done manually
# if [[ -d "third-party/tt-metal/.git" ]]; then
#   git submodule sync
#   git submodule update --init --recursive
#   git submodule foreach 'git lfs fetch --all || true; git lfs pull || true' || true
# fi

# Build editable with pip, disable build isolation to use local torch from venv
export CMAKE_FLAGS="-DCMAKE_C_COMPILER=${CC};-DCMAKE_CXX_COMPILER=${CXX}"
# python3 setup.py develop
export PIP_NO_BUILD_ISOLATION=1
python3 -m pip install -e . --no-build-isolation || true
python -m pip install -e . --no-build-isolation || true
popd >/dev/null
set +x

echo "[ttnn-cpp-ext] Build finished"

# Устанавливаем верхнеуровневый пакет torch-ttnn (editable), НО без зависимостей,
# чтобы не перетягивать prebuilt torch-2.2.1+cpu поверх локальной сборки из исходников
set -x
pushd "${repo_dir}" >/dev/null
export PIP_NO_BUILD_ISOLATION=1
python -m pip install -e . --no-build-isolation --no-deps || true
python3 -m pip install -e . --no-build-isolation --no-deps || true
popd >/dev/null
set +x

# Run smoke test to validate imports
set -x
python "${workspace_dir}/scripts/ttnn_smoke.py"
set +x

