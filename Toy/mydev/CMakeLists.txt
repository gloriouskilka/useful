cmake_minimum_required(VERSION 3.19)
project(mydev_backend LANGUAGES CXX)

# ВАЖНО: используем C++17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Явно выключаем CUDA/ROCm при использовании wheel с cu12, чтобы избежать попыток enable_language(CUDA)
set(USE_CUDA OFF CACHE BOOL "Disable CUDA in Torch CMake")
set(USE_ROCM OFF CACHE BOOL "Disable ROCm in Torch CMake")

# Находим PyTorch (через vcpkg или через Torch_DIR из Python wheel)
# Рекомендуемый способ — через CONFIG-режим
find_package(Torch REQUIRED CONFIG)

# Собираем SHARED-библиотеку без pybind11 — будем грузить через torch.ops.load_library
add_library(mydev_backend SHARED src/mydev_backend.cpp)

# Флаги компиляции (опционально)
if (MSVC)
  target_compile_options(mydev_backend PRIVATE /EHsc)
else()
  target_compile_options(mydev_backend PRIVATE -fPIC -fvisibility=hidden)
endif()

# Линкуем на доступную цель Torch
if (TARGET Torch::Torch)
  target_link_libraries(mydev_backend PRIVATE Torch::Torch)
elseif (TARGET torch)
  target_link_libraries(mydev_backend PRIVATE torch)
else()
  message(FATAL_ERROR "Не найдена цель Torch::Torch или torch для линковки")
endif()

# На Linux итоговый файл будет: mydev_backend.so в build/
set_target_properties(mydev_backend PROPERTIES PREFIX "")


