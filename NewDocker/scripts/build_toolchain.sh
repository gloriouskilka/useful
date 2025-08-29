#!/usr/bin/env bash
set -Eeuo pipefail

# Global flags: image is no-AVX by default; allow override
: "${NO_AVX_FLAGS:=-mno-avx -mno-avx2 -mno-sse4.2 -mno-sse4.1}"
export CFLAGS="${NO_AVX_FLAGS}"
export CXXFLAGS="${NO_AVX_FLAGS}"

num_procs() { nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4; }

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
  ./bootstrap.sh
  # По умолчанию НЕ собираем Boost.Python/Boost.NumPy, т.к. часто ломаются из-за Python/Numpy ABI
  # Можно включить сборку всех библиотек (кроме python/numpy) установив BOOST_BUILD_ALL=1
  if [[ "${BOOST_BUILD_ALL:-0}" == "1" ]]; then
    echo "[build] Boost: build ALL (except python/numpy)"
    ./b2 install --prefix=/usr/local cxxflags="${CXXFLAGS}" -j"$(num_procs)" \
      --without-python --without-numpy
  else
    echo "[build] Boost: build minimal set (headers, system, filesystem, thread, chrono, atomic, regex)"
    # В режиме minimal не указываем --without*, чтобы не конфликтовать с --with*
    ./b2 install --prefix=/usr/local cxxflags="${CXXFLAGS}" -j"$(num_procs)" \
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
  cmake -S /tmp/pybind11 -B /tmp/pybind11/build -DCMAKE_BUILD_TYPE=Release -DPYBIND11_TEST=OFF -DPYBIND11_INSTALL=ON -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}"
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
  cmake -S /tmp/range-v3 -B /tmp/range-v3/build -DCMAKE_BUILD_TYPE=Release -DRANGE_V3_TESTS=OFF -DRANGE_V3_EXAMPLES=OFF -DRANGE_V3_DOCS=OFF -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}"
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
  cmake -S /tmp/taskflow -B /tmp/taskflow/build -DCMAKE_BUILD_TYPE=Release -DTF_BUILD_TESTS=OFF -DTF_BUILD_EXAMPLES=OFF -DTF_BUILD_BENCHMARKS=OFF -DTF_BUILD_CUDA=OFF -DTF_BUILD_SYCL=OFF -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}"
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
  cmake -S /tmp/xtensor_xtl -B /tmp/xtensor_xtl/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}"
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
  cmake -S /tmp/cba/ -B /tmp/cba/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}"
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

main() {
  echo "[build] NO_AVX_FLAGS='${NO_AVX_FLAGS}'"
  install_ccache
  build_boost
  build_pybind11
  build_range_v3
  build_taskflow
  build_xtl
  install_doxygen
  install_cba
  build_iwyu
  echo "[build] Done."
}

main "$@"


