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
python3 -m pip install -e . --no-build-isolation --no-deps
popd >/dev/null
set +x

echo "[ttnn-cpp-ext] Build finished"

# Optionally install top-level torch-ttnn package (editable) to expose Python API
# This will also install its runtime deps (e.g., ttnn, torchvision, torch if versions differ)
set -x
pushd "${repo_dir}" >/dev/null
python -m pip install -e . --no-build-isolation
popd >/dev/null
set +x

# Run smoke test to validate imports
set -x
python "${workspace_dir}/scripts/ttnn_smoke.py"
set +x

