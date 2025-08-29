ARG UBUNTU_VERSION=22.04
FROM public.ecr.aws/ubuntu/ubuntu:${UBUNTU_VERSION} AS base

ENV DEBIAN_FRONTEND=noninteractive

# Позволяет указать путь к исходникам tt-metal в build-контексте.
# В вашем проекте исходники находятся по пути ниже:
ARG TT_METAL_SRC=pytorch2.0_ttnn/torch_ttnn/cpp_extension/third-party/tt-metal

# Установка системных зависимостей через оригинальный скрипт tt-metal
# Копируем скрипты в ожидаемое расположение и запускаем в режиме runtime
COPY ${TT_METAL_SRC}/install_dependencies.sh /opt/tt_metal_infra/scripts/docker/install_dependencies.sh
# Разместим sfpi-version там, где первым делом ищет скрипт: $(dirname $0)/tt_metal/sfpi-version.sh
RUN mkdir -p /opt/tt_metal_infra/scripts/docker/tt_metal
COPY ${TT_METAL_SRC}/tt_metal/sfpi-version.sh /opt/tt_metal_infra/scripts/docker/tt_metal/sfpi-version.sh
RUN /bin/bash /opt/tt_metal_infra/scripts/docker/install_dependencies.sh --docker --mode runtime

#################################################################
# ci-build: добавляем тулчейн и сторонние либы, как в tt-metal
#################################################################
FROM base AS ci-build
RUN /bin/bash /opt/tt_metal_infra/scripts/docker/install_dependencies.sh --docker --mode build

# Установка ccache из апстрима (версия с remote_storage)
RUN mkdir -p /usr/local/bin \
    && wget -O /tmp/ccache.tar.xz https://github.com/ccache/ccache/releases/download/v4.10.2/ccache-4.10.2-linux-x86_64.tar.xz \
    && tar -xf /tmp/ccache.tar.xz -C /usr/local/bin --strip-components=1 \
    && rm /tmp/ccache.tar.xz

# Boost
ARG BOOST_VERSION=1.86.0
RUN mkdir -p /tmp/boost \
    && BOOST_VERSION_UNDERSCORE=$(echo ${BOOST_VERSION} | sed 's/\./_/g') \
    && wget -O /tmp/boost/boost_${BOOST_VERSION}.tar.gz "https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${BOOST_VERSION_UNDERSCORE}.tar.gz" \
    && tar -xzf /tmp/boost/boost_${BOOST_VERSION}.tar.gz -C /tmp/boost --strip-components=1 \
    && cd /tmp/boost \
    && ./bootstrap.sh \
    && ./b2 install --prefix=/usr/local \
    && rm -rf /tmp/boost

# pybind11
ARG PYBIND11_VERSION=2.13.6
RUN mkdir -p /tmp/pybind11 \
    && wget -O /tmp/pybind11/pybind11-${PYBIND11_VERSION}.tar.gz "https://github.com/pybind/pybind11/archive/refs/tags/v${PYBIND11_VERSION}.tar.gz" \
    && tar -xzf /tmp/pybind11/pybind11-${PYBIND11_VERSION}.tar.gz -C /tmp/pybind11 --strip-components=1 \
    && cmake -S /tmp/pybind11 -B /tmp/pybind11/build -DCMAKE_BUILD_TYPE=Release -DPYBIND11_TEST=OFF -DPYBIND11_INSTALL=ON \
    && make -C /tmp/pybind11/build -j$(nproc) \
    && make -C /tmp/pybind11/build install \
    && rm -rf /tmp/pybind11

# range-v3
ARG RANGE_V3_VERSION=0.12.0
RUN mkdir -p /tmp/range-v3 \
    && wget -O /tmp/range-v3/range-v3-${RANGE_V3_VERSION}.tar.gz "https://github.com/ericniebler/range-v3/archive/refs/tags/${RANGE_V3_VERSION}.tar.gz" \
    && tar -xzf /tmp/range-v3/range-v3-${RANGE_V3_VERSION}.tar.gz -C /tmp/range-v3 --strip-components=1 \
    && cmake -S /tmp/range-v3 -B /tmp/range-v3/build -DCMAKE_BUILD_TYPE=Release -DRANGE_V3_TESTS=OFF -DRANGE_V3_EXAMPLES=OFF -DRANGE_V3_DOCS=OFF -DCMAKE_INSTALL_PREFIX=/usr/local \
    && make -C /tmp/range-v3/build -j$(nproc) \
    && make -C /tmp/range-v3/build install \
    && rm -rf /tmp/range-v3

# taskflow
ARG TAKSFLOW_VERSION=3.7.0
RUN mkdir -p /tmp/taskflow \
    && wget -O /tmp/taskflow/taskflow-${TAKSFLOW_VERSION}.tar.gz "https://github.com/taskflow/taskflow/archive/v${TAKSFLOW_VERSION}.tar.gz" \
    && tar -xzf /tmp/taskflow/taskflow-${TAKSFLOW_VERSION}.tar.gz -C /tmp/taskflow --strip-components=1 \
    && cmake -S /tmp/taskflow -B /tmp/taskflow/build -DCMAKE_BUILD_TYPE=Release -DTF_BUILD_TESTS=OFF -DTF_BUILD_EXAMPLES=OFF -DTF_BUILD_BENCHMARKS=OFF -DTF_BUILD_CUDA=OFF -DTF_BUILD_SYCL=OFF \
    && make -C /tmp/taskflow/build -j$(nproc) \
    && make -C /tmp/taskflow/build install \
    && rm -rf /tmp/taskflow

# xtl (xtensor xtl)
ARG XTENSOR_XTL_VERSION=0.8.0
RUN mkdir -p /tmp/xtensor_xtl \
    && wget -O /tmp/xtensor_xtl/xtensor_xtl-${XTENSOR_XTL_VERSION}.tar.gz "https://github.com/xtensor-stack/xtl/archive/refs/tags/${XTENSOR_XTL_VERSION}.tar.gz" \
    && tar -xzf /tmp/xtensor_xtl/xtensor_xtl-${XTENSOR_XTL_VERSION}.tar.gz -C /tmp/xtensor_xtl --strip-components=1 \
    && cmake -S /tmp/xtensor_xtl -B /tmp/xtensor_xtl/build -DCMAKE_BUILD_TYPE=Release \
    && make -C /tmp/xtensor_xtl/build -j$(nproc) \
    && make -C /tmp/xtensor_xtl/build install \
    && rm -rf /tmp/xtensor_xtl

# doxygen
ARG DOXYGEN_VERSION=1.9.6
RUN mkdir -p /tmp/doxygen \
    && wget -O /tmp/doxygen/doxygen-${DOXYGEN_VERSION}.linux.bin.tar.gz "https://www.doxygen.nl/files/doxygen-${DOXYGEN_VERSION}.linux.bin.tar.gz" \
    && tar -xzf /tmp/doxygen/doxygen-${DOXYGEN_VERSION}.linux.bin.tar.gz -C /tmp/doxygen --strip-components=1 \
    && make -C /tmp/doxygen -j$(nproc) \
    && make -C /tmp/doxygen install \
    && rm -rf /tmp/doxygen

# ClangBuildAnalyzer
RUN mkdir -p /tmp/cba \
    && wget -O /tmp/cba/cba.tar.gz https://github.com/aras-p/ClangBuildAnalyzer/archive/refs/tags/v1.6.0.tar.gz \
    && tar -xzf /tmp/cba/cba.tar.gz -C /tmp/cba --strip-components=1 \
    && cmake -S /tmp/cba/ -B /tmp/cba/build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /tmp/cba/build \
    && cmake --install /tmp/cba/build \
    && rm -rf /tmp/cba

# Доп. пакеты apt для ci/dev
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-utils \
    bc \
    libclang-17-dev \
    clang-tidy-17 \
    curl \
    dialog \
    file \
    graphviz \
    jq \
    pandoc \
    sudo \
    uuid-runtime \
    wget \
    libtbb-dev \
    libcapstone-dev \
    libgtest-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Виртуальное окружение, как в tt-metal
ENV PYTHON_ENV_DIR=/opt/venv
RUN python3 -m venv $PYTHON_ENV_DIR
ENV PATH="$PYTHON_ENV_DIR/bin:$PATH"
ENV VIRTUAL_ENV="$PYTHON_ENV_DIR"
RUN echo "source $PYTHON_ENV_DIR/bin/activate" >> /etc/bash.bashrc

# numpy требуется для сборки tt-train
RUN python3 -m pip install --no-cache-dir --upgrade pip \
    && python3 -m pip config set global.extra-index-url https://download.pytorch.org/whl/cpu \
    && python3 -m pip install --no-cache-dir build numpy setuptools

RUN git config --global --add safe.directory '*'
ENV CCACHE_TEMPDIR=/tmp/ccache

#################################################################
# ci-test: установка python-зависимостей из исходников tt-metal
#################################################################
FROM ci-build AS ci-test

ARG TT_METAL_INFRA_DIR=/opt/tt_metal_infra
ARG TT_METAL_SRC=tt-metal
ARG INSTALL_DEV_REQS=0
ENV INSTALL_DEV_REQS=${INSTALL_DEV_REQS}

RUN mkdir -p ${TT_METAL_INFRA_DIR}/tt-metal/docs/ \
    && mkdir -p ${TT_METAL_INFRA_DIR}/tt-metal/tests/sweep_framework/ \
    && mkdir -p ${TT_METAL_INFRA_DIR}/tt-metal/tt_metal/python_env/

COPY ${TT_METAL_SRC}/docs/requirements-docs.txt ${TT_METAL_INFRA_DIR}/tt-metal/docs/requirements-docs.txt
COPY ${TT_METAL_SRC}/tests/sweep_framework/requirements-sweeps.txt ${TT_METAL_INFRA_DIR}/tt-metal/tests/sweep_framework/requirements-sweeps.txt
COPY ${TT_METAL_SRC}/tt_metal/python_env/requirements-dev.txt ${TT_METAL_INFRA_DIR}/tt-metal/tt_metal/python_env/requirements-dev.txt

RUN python3 -m pip config set global.extra-index-url https://download.pytorch.org/whl/cpu \
    && if [ "$INSTALL_DEV_REQS" = "1" ]; then python3 -m pip install --no-cache-dir -r ${TT_METAL_INFRA_DIR}/tt-metal/tt_metal/python_env/requirements-dev.txt; fi \
    && if [ "$INSTALL_DEV_REQS" = "1" ]; then python3 -m pip install --no-cache-dir -r ${TT_METAL_INFRA_DIR}/tt-metal/docs/requirements-docs.txt; fi \
    && chmod -R 777 $VIRTUAL_ENV

#################################################################
# dev: финальный слой для разработки (как в tt-metal dev)
#################################################################
FROM ci-test AS dev

RUN apt-get update && apt-get install -y --no-install-recommends \
    acl \
    emacs \
    gdb \
    less \
    libmpfr-dev \
    nano \
    openssh-server \
    vim \
    libgl1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# IWYU
RUN mkdir -p /tmp/iwyu \
    && wget -O /tmp/iwyu/iwyu.tar.gz https://github.com/include-what-you-use/include-what-you-use/archive/refs/tags/0.21.tar.gz \
    && tar -xzf /tmp/iwyu/iwyu.tar.gz -C /tmp/iwyu --strip-components=1 \
    && cmake -S /tmp/iwyu/ -B /tmp/iwyu/build -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang-17 -DCMAKE_CXX_COMPILER=clang++-17 \
    && cmake --build /tmp/iwyu/build --parallel \
    && cmake --install /tmp/iwyu/build \
    && rm -rf /tmp/iwyu

# Если не 24.04 — пересобрать gdb 14.2 (как в оригинале)
RUN [ "$UBUNTU_VERSION" != "24.04" ] && apt-get remove -y gdb || true
RUN [ "$UBUNTU_VERSION" != "24.04" ] \
    && mkdir -p /tmp/gdb-build && cd /tmp/gdb-build/ \
    && wget -O /tmp/gdb-build/gdb.tar.gz https://ftp.gnu.org/gnu/gdb/gdb-14.2.tar.gz \
    && tar -xvf /tmp/gdb-build/gdb.tar.gz -C /tmp/gdb-build --strip-components=1 \
    && /tmp/gdb-build/configure --prefix=/usr/local \
    && make -j$(nproc) \
    && make install \
    && rm -rf /tmp/gdb-build || true

WORKDIR /workspace
CMD ["bash"]


