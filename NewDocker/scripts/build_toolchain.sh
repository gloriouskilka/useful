#!/usr/bin/env bash
set -Eeuo pipefail

# Global flags: image is no-AVX by default; allow override
: "${NO_AVX_FLAGS:=-mno-avx -mno-avx2 -mno-sse4.2 -mno-sse4.1}"
export CFLAGS="${NO_AVX_FLAGS}"
export CXXFLAGS="${NO_AVX_FLAGS}"

# Prefer clang-17 toolchain by default for ABI compatibility with PyTorch/pybind
# Allow override from environment if explicitly set by user
: "${CC:=clang-17}"
: "${CXX:=clang++-17}"
export CC
export CXX

num_procs() { nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4; }

# Stamps directory to mark completed steps (idempotent runs)
: "${TOOLCHAIN_STAMP_DIR:=$(pwd)/.toolchain_stamps}"; export TOOLCHAIN_STAMP_DIR
mkdir -p "${TOOLCHAIN_STAMP_DIR}" || true

# Verbose git diagnostics by default (can be overridden by user)
: "${GIT_TRACE:=1}"; export GIT_TRACE
: "${GIT_CURL_VERBOSE:=1}"; export GIT_CURL_VERBOSE

log_git_overrides() {
  echo "[git-debug] Global URL overrides:"
  git config --global -l | grep -E '^url\.' || true
}

rewrite_to_https_in_gitmodules() {
  # Args: path to repo (defaults to current)
  local repo_dir
  repo_dir="${1:-$(pwd)}"
  if [[ -f "${repo_dir}/.gitmodules" ]]; then
    echo "[git-debug] .gitmodules BEFORE rewrite:"; cat "${repo_dir}/.gitmodules" || true
    sed -i 's|git@github.com:|https://github.com/|g' "${repo_dir}/.gitmodules" || true
    sed -i 's|ssh://git@github.com/|https://github.com/|g' "${repo_dir}/.gitmodules" || true
    sed -i 's|git://github.com/|https://github.com/|g' "${repo_dir}/.gitmodules" || true
    echo "[git-debug] .gitmodules AFTER rewrite:"; cat "${repo_dir}/.gitmodules" || true
  else
    echo "[git-debug] No .gitmodules in ${repo_dir}"
  fi
}

# Try to export Torch_DIR if built-from-source layout is present
export_torch_dir_guess() {
  local workspace_dir pytorch_dir torch_cmake_dir
  workspace_dir="$(pwd)"
  pytorch_dir="${workspace_dir}/pytorch"
  torch_cmake_dir="${pytorch_dir}/torch/share/cmake/Torch"
  if [[ -d "${torch_cmake_dir}" ]]; then
    export Torch_DIR="${torch_cmake_dir}"
    echo "[pytorch] Using Torch_DIR guess: ${Torch_DIR}"
    # Persist for future shells
    if ! grep -q "export Torch_DIR=\"${Torch_DIR}\"" /root/.bashrc 2>/dev/null; then
      echo "export Torch_DIR=\"${Torch_DIR}\"" >> /root/.bashrc
      echo "[pytorch] Persisted Torch_DIR to /root/.bashrc"
    fi
    return 0
  fi
  return 1
}

ensure_clang_aliases() {
  # Ensure generic clang/clang++ are available for tools (e.g., Boost b2) expecting these names
  local clang_bin clangxx_bin
  clang_bin="$(command -v clang-17 || true)"
  clangxx_bin="$(command -v clang++-17 || true)"
  mkdir -p /usr/local/bin
  if ! command -v clang >/dev/null 2>&1 && [[ -n "${clang_bin}" ]]; then
    ln -sf "${clang_bin}" /usr/local/bin/clang
  fi
  if ! command -v clang++ >/dev/null 2>&1 && [[ -n "${clangxx_bin}" ]]; then
    ln -sf "${clangxx_bin}" /usr/local/bin/clang++
  fi
}

install_ccache() {
  if command -v ccache >/dev/null 2>&1; then
    echo "[build] ccache already present: $(ccache --version | head -n1)"; return 0; fi
  local arch
  arch="$(uname -m)"
  local tar_arch
  if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then tar_arch=aarch64; else tar_arch=x86_64; fi
  echo "[build] Installing ccache for ${tar_arch}"
  mkdir -p /usr/local/bin
  wget -O /tmp/ccache.tar.xz "https://github.com/ccache/ccache/releases/download/v4.10.2/ccache-4.10.2-linux-${tar_arch}.tar.xz"
  tar -xf /tmp/ccache.tar.xz -C /usr/local/bin --strip-components=1
  rm -f /tmp/ccache.tar.xz
}

build_boost() {
  if [[ "${FORCE_BOOST_REBUILD:-0}" != "1" && -f /usr/local/include/boost/version.hpp ]]; then echo "[build] Boost already installed"; return 0; fi
  local ver=${BOOST_VERSION:-1.86.0}
  local ver_uscore
  ver_uscore="${ver//./_}"
  echo "[build] Building Boost ${ver}"
  if [[ "${FORCE_BOOST_REBUILD:-0}" == "1" ]]; then
    echo "[build] FORCE_BOOST_REBUILD=1: cleaning previous Boost install from /usr/local"
    rm -rf /usr/local/include/boost || true
    rm -f /usr/local/lib/libboost_* || true
    rm -rf /usr/local/lib/cmake/Boost* /usr/local/lib/cmake/boost_* || true
  fi
  mkdir -p /tmp/boost
  wget -O /tmp/boost/boost_${ver}.tar.gz "https://archives.boost.io/release/${ver}/source/boost_${ver_uscore}.tar.gz"
  tar -xzf /tmp/boost/boost_${ver}.tar.gz -C /tmp/boost --strip-components=1
  pushd /tmp/boost >/dev/null
  # Prefer clang toolset for ABI compatibility; bootstrap with explicit toolset
  CC="${CC}" CXX="${CXX}" ./bootstrap.sh --with-toolset=clang || ./bootstrap.sh
  # По умолчанию НЕ собираем Boost.Python/Boost.NumPy, т.к. часто ломаются из-за Python/Numpy ABI
  # Можно включить сборку всех библиотек (кроме python/numpy) установив BOOST_BUILD_ALL=1
  if [[ "${BOOST_BUILD_ALL:-0}" == "1" ]]; then
    echo "[build] Boost: build ALL (except python/numpy)"
    ./b2 install --prefix=/usr/local cxxflags="${CXXFLAGS}" toolset=clang -j"$(num_procs)" \
      --without-python --without-numpy
  else
    echo "[build] Boost: build minimal set (headers, system, filesystem, thread, chrono, atomic, regex)"
    # В режиме minimal не указываем --without*, чтобы не конфликтовать с --with*
    ./b2 install --prefix=/usr/local cxxflags="${CXXFLAGS}" toolset=clang -j"$(num_procs)" \
      --with-headers --with-system --with-filesystem --with-thread --with-chrono --with-atomic --with-regex
  fi
  popd >/dev/null
  rm -rf /tmp/boost
}

build_pybind11() {
  if [[ -f /usr/local/include/pybind11/pybind11.h ]]; then echo "[build] pybind11 already installed"; return 0; fi
  local ver=${PYBIND11_VERSION:-2.13.6}
  echo "[build] Building pybind11 ${ver}"
  mkdir -p /tmp/pybind11
  wget -O /tmp/pybind11/pybind11-${ver}.tar.gz "https://github.com/pybind/pybind11/archive/refs/tags/v${ver}.tar.gz"
  tar -xzf /tmp/pybind11/pybind11-${ver}.tar.gz -C /tmp/pybind11 --strip-components=1
  cmake -S /tmp/pybind11 -B /tmp/pybind11/build -DCMAKE_BUILD_TYPE=Release -DPYBIND11_TEST=OFF -DPYBIND11_INSTALL=ON -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" -DCMAKE_C_COMPILER="${CC}" -DCMAKE_CXX_COMPILER="${CXX}"
  cmake --build /tmp/pybind11/build --parallel "$(num_procs)"
  cmake --install /tmp/pybind11/build
  rm -rf /tmp/pybind11
}

build_range_v3() {
  if [[ -f /usr/local/include/range/v3/version.hpp ]]; then echo "[build] range-v3 already installed"; return 0; fi
  local ver=${RANGE_V3_VERSION:-0.12.0}
  echo "[build] Building range-v3 ${ver}"
  mkdir -p /tmp/range-v3
  wget -O /tmp/range-v3/range-v3-${ver}.tar.gz "https://github.com/ericniebler/range-v3/archive/refs/tags/${ver}.tar.gz"
  tar -xzf /tmp/range-v3/range-v3-${ver}.tar.gz -C /tmp/range-v3 --strip-components=1
  cmake -S /tmp/range-v3 -B /tmp/range-v3/build -DCMAKE_BUILD_TYPE=Release -DRANGE_V3_TESTS=OFF -DRANGE_V3_EXAMPLES=OFF -DRANGE_V3_DOCS=OFF -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" -DCMAKE_C_COMPILER="${CC}" -DCMAKE_CXX_COMPILER="${CXX}"
  cmake --build /tmp/range-v3/build --parallel "$(num_procs)"
  cmake --install /tmp/range-v3/build
  rm -rf /tmp/range-v3
}

build_taskflow() {
  if [[ -f /usr/local/include/taskflow/taskflow.hpp ]]; then echo "[build] taskflow already installed"; return 0; fi
  local ver=${TAKSFLOW_VERSION:-3.7.0}
  echo "[build] Building taskflow ${ver}"
  mkdir -p /tmp/taskflow
  wget -O /tmp/taskflow/taskflow-${ver}.tar.gz "https://github.com/taskflow/taskflow/archive/v${ver}.tar.gz"
  tar -xzf /tmp/taskflow/taskflow-${ver}.tar.gz -C /tmp/taskflow --strip-components=1
  cmake -S /tmp/taskflow -B /tmp/taskflow/build -DCMAKE_BUILD_TYPE=Release -DTF_BUILD_TESTS=OFF -DTF_BUILD_EXAMPLES=OFF -DTF_BUILD_BENCHMARKS=OFF -DTF_BUILD_CUDA=OFF -DTF_BUILD_SYCL=OFF -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" -DCMAKE_C_COMPILER="${CC}" -DCMAKE_CXX_COMPILER="${CXX}"
  cmake --build /tmp/taskflow/build --parallel "$(num_procs)"
  cmake --install /tmp/taskflow/build
  rm -rf /tmp/taskflow
}

build_xtl() {
  if [[ -f /usr/local/include/xtl/xtl_config.hpp ]]; then echo "[build] xtl already installed"; return 0; fi
  local ver=${XTENSOR_XTL_VERSION:-0.8.0}
  echo "[build] Building xtl ${ver}"
  mkdir -p /tmp/xtensor_xtl
  wget -O /tmp/xtensor_xtl/xtensor_xtl-${ver}.tar.gz "https://github.com/xtensor-stack/xtl/archive/refs/tags/${ver}.tar.gz"
  tar -xzf /tmp/xtensor_xtl/xtensor_xtl-${ver}.tar.gz -C /tmp/xtensor_xtl --strip-components=1
  cmake -S /tmp/xtensor_xtl -B /tmp/xtensor_xtl/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" -DCMAKE_C_COMPILER="${CC}" -DCMAKE_CXX_COMPILER="${CXX}"
  cmake --build /tmp/xtensor_xtl/build --parallel "$(num_procs)"
  cmake --install /tmp/xtensor_xtl/build
  rm -rf /tmp/xtensor_xtl
}

install_doxygen() {
  if command -v doxygen >/dev/null 2>&1; then echo "[build] doxygen already present"; return 0; fi
  local ver=${DOXYGEN_VERSION:-1.9.6}
  echo "[build] Installing doxygen ${ver}"
  mkdir -p /tmp/doxygen
  wget -O /tmp/doxygen/doxygen-${ver}.linux.bin.tar.gz "https://www.doxygen.nl/files/doxygen-${ver}.linux.bin.tar.gz"
  tar -xzf /tmp/doxygen/doxygen-${ver}.linux.bin.tar.gz -C /tmp/doxygen --strip-components=1
  make -C /tmp/doxygen -j"$(num_procs)"
  make -C /tmp/doxygen install
  rm -rf /tmp/doxygen
}

install_cba() {
  if command -v ClangBuildAnalyzer >/dev/null 2>&1; then echo "[build] CBA already present"; return 0; fi
  echo "[build] Installing ClangBuildAnalyzer"
  mkdir -p /tmp/cba
  wget -O /tmp/cba/cba.tar.gz https://github.com/aras-p/ClangBuildAnalyzer/archive/refs/tags/v1.6.0.tar.gz
  tar -xzf /tmp/cba/cba.tar.gz -C /tmp/cba --strip-components=1
  cmake -S /tmp/cba/ -B /tmp/cba/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" -DCMAKE_C_COMPILER="${CC}" -DCMAKE_CXX_COMPILER="${CXX}"
  cmake --build /tmp/cba/build --parallel "$(num_procs)"
  cmake --install /tmp/cba/build
  rm -rf /tmp/cba
}

build_iwyu() {
  if command -v include-what-you-use >/dev/null 2>&1; then echo "[build] IWYU already present"; return 0; fi
  echo "[build] Building IWYU"
  mkdir -p /tmp/iwyu
  wget -O /tmp/iwyu/iwyu.tar.gz https://github.com/include-what-you-use/include-what-you-use/archive/refs/tags/0.21.tar.gz
  tar -xzf /tmp/iwyu/iwyu.tar.gz -C /tmp/iwyu --strip-components=1
  cmake -S /tmp/iwyu/ -B /tmp/iwyu/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang-17 -DCMAKE_CXX_COMPILER=clang++-17 -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}"
  cmake --build /tmp/iwyu/build --parallel "$(num_procs)"
  cmake --install /tmp/iwyu/build
  rm -rf /tmp/iwyu
}

# --------------------------------------------------------------------------------------
# По-новому: упорядоченная сборка
# 1) Сбор зависимостей (как в tt-metal Dockerfile)
# 2) Сборка PyTorch из исходников (совместимый ABI, clang-17)
# 3) Сборка tt-metal, используя только что собранный PyTorch в окружении
# --------------------------------------------------------------------------------------

# Поиск каталога tt-metal в workspace
find_tt_metal_dir() {
  local tt_metal_dir="/workspace/pytorch2.0_ttnn/torch_ttnn/cpp_extension/third-party/tt-metal"
  if [[ -f "${tt_metal_dir}/install_dependencies.sh" ]]; then
    echo "${tt_metal_dir}"
    return 0
  fi
  echo "[tt-metal] ERROR: expected tt-metal at ${tt_metal_dir}" >&2
  return 1
}

# Сборка PyTorch из исходников с clang-17
build_pytorch_from_source() {
  echo "[pytorch] Build from source"

  # 2.1 Подготовка Python окружения
  if [[ -x "/opt/venv/bin/activate" ]]; then
    # shellcheck disable=SC1091
    source /opt/venv/bin/activate
    echo "[pytorch] Using venv: /opt/venv"
  fi
  python -m pip config set global.extra-index-url https://download.pytorch.org/whl/cpu || true
  python -m pip install --upgrade pip setuptools wheel

  # 2.2 Сносим колёсные сборки torch, если установлены
  python -m pip uninstall -y torch torchvision torchmetrics torch-fidelity || true

  # 2.3 Системная зависимость (OMP для clang-17)
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y || true
    apt-get install -y --no-install-recommends libomp-17-dev || true
  fi

  # 2.4 Получаем исходники PyTorch совместимой версии
  local workspace_dir pytorch_dir pytorch_ver
  workspace_dir="$(pwd)"
  pytorch_dir="${workspace_dir}/pytorch"
  pytorch_ver="${PYTORCH_VERSION:-v2.2.1}"
  if [[ ! -d "${pytorch_dir}/.git" ]]; then
    echo "[pytorch][git] Cloning https://github.com/pytorch/pytorch.git into ${pytorch_dir}"
    git clone https://github.com/pytorch/pytorch.git "${pytorch_dir}" || { echo "[pytorch][git][ERROR] clone failed"; exit 1; }
  fi
  pushd "${pytorch_dir}" >/dev/null
  # Force HTTPS for all GitHub operations (avoid SSH keys in containers)
  git config --global url.https://github.com/.insteadOf git@github.com:
  git config --global url.https://github.com/.insteadOf ssh://git@github.com/
  git config --global url.https://github.com/.insteadOf git://github.com/
  log_git_overrides
  echo "[pytorch][git] Remote BEFORE set-url:"; git remote -v || true
  git remote set-url origin https://github.com/pytorch/pytorch.git || true
  echo "[pytorch][git] Remote AFTER set-url:"; git remote -v || true
  # Rewrite submodule URLs inside .gitmodules from SSH to HTTPS (defensive)
  rewrite_to_https_in_gitmodules "${pytorch_dir}"
  echo "[pytorch][git] Disable maintenance.auto and fetch tags (verbose)"
  git config --global maintenance.auto false || true
  if ! git -c maintenance.auto=false fetch --tags --verbose; then
    echo "[pytorch][git][WARN] fetch --tags returned non-zero. Verifying connectivity via ls-remote..."
    if git -c maintenance.auto=false ls-remote --tags origin >/dev/null 2>&1; then
      echo "[pytorch][git][INFO] ls-remote succeeded; proceeding despite fetch return code."
    else
      echo "[pytorch][git][ERROR] both fetch --tags and ls-remote failed"; exit 1;
    fi
  fi
  echo "[pytorch][git] Checkout tags/${pytorch_ver}"
  git checkout "tags/${pytorch_ver}" || { echo "[pytorch][git][ERROR] checkout ${pytorch_ver} failed"; exit 1; }
  echo "[pytorch][git] Submodule sync --recursive"
  git submodule sync --recursive || { echo "[pytorch][git][ERROR] submodule sync failed"; exit 1; }
  echo "[pytorch][git] Submodule update --init --recursive"
  git submodule update --init --recursive || { echo "[pytorch][git][ERROR] submodule update failed"; exit 1; }

  # 2.5 Python-зависимости PyTorch
  python -m pip install mkl-static mkl-include
  python -m pip install -U numpy==1.26.4
  python -m pip install -r requirements.txt

  # 2.6 Сборка PyTorch (разделяемая, develop)
  echo "[pytorch] Cleaning previous build dir"
  rm -rf build || true
  echo "[pytorch] Building with CC=${CC} CXX=${CXX} (CPU-only, no-MPI)"
  export CMAKE_GENERATOR="Ninja"
  export CMAKE_ARGS="-DUSE_MPI=OFF;-DUSE_DISTRIBUTED=ON;-DUSE_NCCL=OFF;-DUSE_CUDA=OFF;-DUSE_ROCM=OFF"
  USE_CUDA=0 \
  USE_ROCM=0 \
  USE_NCCL=0 \
  USE_MPI=0 \
  USE_DISTRIBUTED=1 \
  BUILD_TEST=0 \
  CC="${CC}" CXX="${CXX}" CMAKE_POLICY_VERSION_MINIMUM=3.5 python setup.py develop
  popd >/dev/null
  echo "[pytorch] Done"

  # Export Torch_DIR for comfortable CMake usage in the current and future shells
  local torch_cmake_dir
  torch_cmake_dir="${pytorch_dir}/torch/share/cmake/Torch"
  if [[ -d "${torch_cmake_dir}" ]]; then
    echo "[pytorch] Detected Torch CMake dir: ${torch_cmake_dir}"
    export Torch_DIR="${torch_cmake_dir}"
    # Persist in root's bashrc inside container
    if ! grep -q "export Torch_DIR=\"${torch_cmake_dir}\"" /root/.bashrc 2>/dev/null; then
      echo "export Torch_DIR=\"${torch_cmake_dir}\"" >> /root/.bashrc
      echo "[pytorch] Persisted Torch_DIR to /root/.bashrc"
    fi
    if ! grep -q "source /opt/venv/bin/activate" /root/.bashrc 2>/dev/null; then
      echo "source /opt/venv/bin/activate" >> /root/.bashrc
      echo "[pytorch] Appended venv activation to /root/.bashrc"
    fi
  else
    echo "[pytorch][WARN] Torch CMake dir not found at ${torch_cmake_dir}. If build_metal fails on Torch_DIR, set it manually."
  fi
}

# Detect if PyTorch is already installed and Torch_DIR available
ensure_pytorch_built() {
  echo "[pytorch] Checking existing installation"
  # Hardcode Torch_DIR as requested (no detection)
  export Torch_DIR="/workspace/pytorch"
  if ! grep -q "export Torch_DIR=\"${Torch_DIR}\"" /root/.bashrc 2>/dev/null; then
    echo "export Torch_DIR=\"${Torch_DIR}\"" >> /root/.bashrc
    echo "[pytorch] Persisted Torch_DIR to /root/.bashrc"
  fi
  local torch_rc=0
  python - <<'PY' || torch_rc=$?
try:
    import torch
    print("torch_version=", torch.__version__)
    print("torch_file=", torch.__file__)
except Exception as e:
    print("torch_import_error=", e)
    raise
PY
  if [[ ${torch_rc} -eq 0 ]]; then
    echo "[pytorch] torch import OK"
    return 0
  fi
  build_pytorch_from_source
}

# Сборка tt-metal после PyTorch
build_tt_metal() {
  echo "[tt-metal] Build using local environment"
  local tt_metal_dir
  if ! tt_metal_dir="$(find_tt_metal_dir)"; then
    echo "[tt-metal] ERROR: tt-metal not found in workspace (./tt-metal or ./pytorch2.0_ttnn/torch_ttnn/cpp_extension/third-party/tt-metal)" >&2
    return 1
  fi
  echo "[tt-metal] TT_METAL_DIR='${tt_metal_dir}'"
  export TT_METAL_HOME="${tt_metal_dir}"
  echo "[tt-metal] Exported TT_METAL_HOME='${TT_METAL_HOME}'"

  # 3.1 Установить зависимости tt-metal (если ещё не поставлены в образе)
  pushd "${tt_metal_dir}" >/dev/null
  if [[ -x ./install_dependencies.sh ]]; then
    bash ./install_dependencies.sh || true
  fi

  # 3.0: Полная очистка по запросу пользователя (через --rebuild)
  if [[ "${REBUILD:-0}" == "1" ]]; then
    echo "[tt-metal] --rebuild: running build_metal.sh --clean"
    bash ./build_metal.sh --clean || true
  fi

  # 3.1.1 Guard: clean build directory if CMakeCache was created for a different source path
  local build_dir cache_file cached_src
  build_dir="${tt_metal_dir}/build"
  cache_file="${build_dir}/CMakeCache.txt"
  if [[ -f "${cache_file}" ]]; then
    cached_src=$(grep -E '^CMAKE_HOME_DIRECTORY:INTERNAL=' "${cache_file}" | sed 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//')
    if [[ -n "${cached_src}" && "${cached_src}" != "${tt_metal_dir}" ]]; then
      echo "[tt-metal][clean] Detected CMakeCache from different source: ${cached_src} != ${tt_metal_dir}. Cleaning ${build_dir}..."
      rm -rf "${build_dir}"
    fi
  fi

  # 3.2 Сборка tt-metal: используем единый каталог build (Release-сборка)
  build_dir="${tt_metal_dir}/build"

  # Проверяем наличие ожидаемых артефактов в build
  local metal_so ttnn_so cmake_config
  metal_so="${build_dir}/lib/libtt_metal.so"
  ttnn_so="${build_dir}/lib/_ttnn.so"
  cmake_config="${build_dir}/tt-metalium-config.cmake"

  if [[ -f "${metal_so}" && -f "${ttnn_so}" && -f "${cmake_config}" && -f "${build_dir}/.noavx_build" ]]; then
    echo "[tt-metal] Existing NOAVX build detected with required artefacts in ${build_dir}; skipping rebuild"
    popd >/dev/null
    echo "[tt-metal] Done"
    return 0
  fi

  echo "[tt-metal] Building (Release) with NOAVX and define NOAVX_BUILD_ONLY"
  echo "[tt-metal] Building with NOAVX and define NOAVX_BUILD_ONLY"
  CFLAGS="${CFLAGS} -DNOAVX_BUILD_ONLY" \
  CXXFLAGS="${CXXFLAGS} -DNOAVX_BUILD_ONLY" \
  bash ./build_metal.sh --enable-ccache --build-type Release --build-dir build
  # Гарантируем наличие каталога build/lib и копируем обязательные артефакты в стандартные имена
  mkdir -p "${build_dir}/lib"
  # libtt_metal.so — если точного файла нет в build/lib, ищем по проекту
  if [[ ! -f "${build_dir}/lib/libtt_metal.so" ]]; then
    metal_alt="$(find "${tt_metal_dir}" -maxdepth 3 -type f -name 'libtt*_metal*.so' | head -n1 || true)"
    if [[ -n "${metal_alt}" ]]; then
      cp -f "${metal_alt}" "${build_dir}/lib/libtt_metal.so"
      echo "[tt-metal][info] Copied ${metal_alt} -> ${build_dir}/lib/libtt_metal.so"
    fi
  fi
  # _ttnn.so — если точного файла нет в build/lib, ищем по проекту
  if [[ ! -f "${build_dir}/lib/_ttnn.so" ]]; then
    ttnn_alt="$(find "${tt_metal_dir}" -maxdepth 3 -type f -name '*ttnn*.so' | head -n1 || true)"
    if [[ -n "${ttnn_alt}" ]]; then
      cp -f "${ttnn_alt}" "${build_dir}/lib/_ttnn.so"
      echo "[tt-metal][info] Copied ${ttnn_alt} -> ${build_dir}/lib/_ttnn.so"
    fi
  fi
  # libdevice.so — опционально (если присутствует)
  if [[ ! -f "${build_dir}/lib/libdevice.so" ]]; then
    device_alt="$(find "${tt_metal_dir}" -maxdepth 3 -type f -name 'libdevice*.so' | head -n1 || true)"
    if [[ -n "${device_alt}" ]]; then
      cp -f "${device_alt}" "${build_dir}/lib/libdevice.so"
      echo "[tt-metal][info] Copied ${device_alt} -> ${build_dir}/lib/libdevice.so"
    fi
  fi
  # Конфиг CMake
  if [[ ! -f "${build_dir}/tt-metalium-config.cmake" ]]; then
    cmake_alt="$(find "${tt_metal_dir}" -maxdepth 2 -type f -name 'tt-metalium-config.cmake' | head -n1 || true)"
    if [[ -n "${cmake_alt}" ]]; then
      cp -f "${cmake_alt}" "${build_dir}/tt-metalium-config.cmake"
      echo "[tt-metal][info] Copied ${cmake_alt} -> ${build_dir}/tt-metalium-config.cmake"
    fi
  fi
  # Флажок о NOAVX-сборке
  touch "${build_dir}/.noavx_build"
  popd >/dev/null
  echo "[tt-metal] Done"
}

main() {
  echo "[build] NO_AVX_FLAGS='${NO_AVX_FLAGS}'"
  echo "[build] CC='${CC}', CXX='${CXX}'"

  # Parse args
  REBUILD=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --rebuild)
        REBUILD=1; shift ;;
      --help|-h)
        echo "Usage: $(basename "$0") [--rebuild]"; return 0 ;;
      *)
        echo "[build] Ignoring unknown arg: $1"; shift ;;
    esac
  done

  # 1) Зависимости (в стиле tt-metal Dockerfile)
  echo "[step 1/3] Dependencies for tt-metal"
  ensure_clang_aliases
  install_ccache
  build_boost
  build_pybind11
  build_range_v3
  build_taskflow
  build_xtl
  install_doxygen
  install_cba
  build_iwyu

  # 2) Сборка PyTorch
  echo "[step 2/3] Build PyTorch from source (skip if present)"
  ensure_pytorch_built

  # 3) Сборка tt-metal на основе локального окружения (PyTorch уже установлен в venv)
  echo "[step 3/3] Build tt-metal"
  build_tt_metal

  echo "[build] All steps finished."
}

main "$@"


