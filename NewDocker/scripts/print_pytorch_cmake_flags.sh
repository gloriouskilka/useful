#!/usr/bin/env bash
set -Eeuo pipefail

# Usage:
#   ./scripts/print_pytorch_cmake_flags.sh [/path/to/pytorch/build/CMakeCache.txt]
# If not provided, defaults to /workspace/pytorch/build/CMakeCache.txt

cache_file="${1:-/workspace/pytorch/build/CMakeCache.txt}"

if [[ ! -f "${cache_file}" ]]; then
  echo "[ERR] CMakeCache.txt not found: ${cache_file}" 1>&2
  exit 1
fi

echo "== Dump selected CMake cache flags =="
echo "FILE: ${cache_file}"

print_key() {
  local key="$1"
  local line
  line=$(grep -E "^${key}(:[^=]+)?=" -m1 "${cache_file}" || true)
  if [[ -z "${line}" ]]; then
    echo "${key}=<not found>"
  else
    # Extract value after '='
    echo "${key}=$(echo "${line}" | sed 's/^.*=//')"
  fi
}

# CPU capability / dispatch
print_key CPU_CAPABILITY
print_key ATEN_CPU_STATIC_DISPATCH
print_key ATEN_CPU_CAPABILITY

# Compiler flags
print_key CMAKE_CXX_FLAGS
print_key CMAKE_C_FLAGS

# AVX-related
print_key USE_AVX
print_key C_HAS_AVX
print_key C_HAS_AVX_2
print_key C_HAS_AVX2_2
print_key CXX_HAS_AVX
print_key CXX_HAS_AVX_2
print_key CXX_HAS_AVX2_2
print_key CAFFE2_COMPILER_SUPPORTS_AVX512_EXTENSIONS

# Backends that may induce x86 paths
print_key USE_FBGEMM
print_key USE_QNNPACK
print_key USE_PYTORCH_QNNPACK
print_key USE_XNNPACK

# BLAS / oneDNN
print_key BLAS
print_key USE_MKLDNN

echo "== End =="


