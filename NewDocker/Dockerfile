ARG UBUNTU_VERSION=22.04
FROM public.ecr.aws/ubuntu/ubuntu:${UBUNTU_VERSION} AS base

# Разрешаем использовать bash в RUN и получаем архитектуру из buildx
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG TARGETARCH
ENV TARGETARCH=${TARGETARCH}

ENV DEBIAN_FRONTEND=noninteractive

# Позволяет указать путь к исходникам tt-metal в build-контексте.
# В вашем проекте исходники находятся по пути ниже:
ARG TT_METAL_SRC=pytorch2.0_ttnn/torch_ttnn/cpp_extension/third-party/tt-metal

# Глобальные no-AVX флаги (собираем всегда без AVX)
ARG NO_AVX_FLAGS="-mno-avx -mno-avx2 -mno-sse4.2 -mno-sse4.1"
ENV NO_AVX_FLAGS=${NO_AVX_FLAGS}
ENV CFLAGS="${NO_AVX_FLAGS}" CXXFLAGS="${NO_AVX_FLAGS}"

# Установка системных зависимостей через оригинальный скрипт tt-metal
# Копируем скрипты в ожидаемое расположение и запускаем в режиме runtime
COPY ${TT_METAL_SRC}/install_dependencies.sh /opt/tt_metal_infra/scripts/docker/install_dependencies.sh
# Разместим sfpi-version там, где первым делом ищет скрипт: $(dirname $0)/tt_metal/sfpi-version.sh
RUN mkdir -p /opt/tt_metal_infra/scripts/docker/tt_metal
COPY ${TT_METAL_SRC}/tt_metal/sfpi-version.sh /opt/tt_metal_infra/scripts/docker/tt_metal/sfpi-version.sh
RUN /bin/bash /opt/tt_metal_infra/scripts/docker/install_dependencies.sh --docker --mode build

#################################################################
# ci-build: добавляем тулчейн и сторонние либы, как в tt-metal
#################################################################
FROM base AS ci-build
ARG TARGETARCH
ENV TARGETARCH=${TARGETARCH}
RUN /bin/bash /opt/tt_metal_infra/scripts/docker/install_dependencies.sh --docker --mode build

# Скрипт сборки тулчейна исполняется из смонтированного workspace внутри контейнера

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
    libnuma-dev \
    libtbb-dev \
    libcapstone-dev \
    libgtest-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Виртуальное окружение, как в tt-metal
ENV PYTHON_ENV_DIR=/opt/venv
RUN apt-get update && apt-get install -y --no-install-recommends python3-venv \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
RUN python3 -m venv $PYTHON_ENV_DIR
ENV PATH="$PYTHON_ENV_DIR/bin:$PATH"
ENV VIRTUAL_ENV="$PYTHON_ENV_DIR"
RUN echo "source $PYTHON_ENV_DIR/bin/activate" >> /etc/bash.bashrc
RUN echo "source /opt/venv/bin/activate" >> /root/.bashrc

# Dev convenience: TT_METAL_HOME points to submodule path under workspace
ENV TT_METAL_HOME=/workspace/pytorch2.0_ttnn/torch_ttnn/cpp_extension/third-party/tt-metal
RUN printf 'export TT_METAL_HOME=/workspace/pytorch2.0_ttnn/torch_ttnn/cpp_extension/third-party/tt-metal\n' > /etc/profile.d/tt_env.sh \
    && chmod +x /etc/profile.d/tt_env.sh \
    && echo 'export TT_METAL_HOME=/workspace/pytorch2.0_ttnn/torch_ttnn/cpp_extension/third-party/tt-metal' >> /root/.bashrc

# Preload tt-metal libs path for runtime (bash shells)
ENV TT_LIB_DIR=/workspace/pytorch2.0_ttnn/torch_ttnn/cpp_extension/third-party/tt-metal/build/lib
RUN echo 'export TT_LIB_DIR=/workspace/pytorch2.0_ttnn/torch_ttnn/cpp_extension/third-party/tt-metal/build/lib' >> /root/.bashrc \
    && echo 'export LD_LIBRARY_PATH="$TT_LIB_DIR:${LD_LIBRARY_PATH:-}"' >> /root/.bashrc

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
ARG TARGETARCH
ENV TARGETARCH=${TARGETARCH}

ARG TT_METAL_INFRA_DIR=/opt/tt_metal_infra
ARG TT_METAL_SRC
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
ARG TARGETARCH
ENV TARGETARCH=${TARGETARCH}

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
    libnuma-dev \
    mc \
    htop \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# IWYU ставится внутри scripts/build_toolchain.sh (по необходимости)

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


