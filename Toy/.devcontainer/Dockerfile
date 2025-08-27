FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Базовые пакеты + Python 3.12 + build toolchain
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git sudo nano vim \
    build-essential ninja-build cmake pkg-config \
    python3 python3-pip python3-venv python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Создаем non-root пользователя vscode (идемпотентно, с учетом уже существующих UID/GID)
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=1000
RUN set -eux; \
    if getent group "${USER_GID}" >/dev/null; then \
      existing_group="$(getent group "${USER_GID}" | cut -d: -f1)"; \
      if [ "${existing_group}" != "${USERNAME}" ]; then groupmod -n "${USERNAME}" "${existing_group}"; fi; \
    else \
      groupadd --gid "${USER_GID}" "${USERNAME}"; \
    fi; \
    existing_user_by_uid="$(getent passwd "${USER_UID}" | cut -d: -f1 || true)"; \
    if [ -n "${existing_user_by_uid}" ] && [ "${existing_user_by_uid}" != "${USERNAME}" ]; then \
      usermod -l "${USERNAME}" "${existing_user_by_uid}"; \
      usermod -d "/home/${USERNAME}" -m "${USERNAME}"; \
    fi; \
    if id -u "${USERNAME}" >/dev/null 2>&1; then \
      usermod -u "${USER_UID}" -g "${USER_GID}" -s /bin/bash "${USERNAME}" || true; \
    else \
      useradd -s /bin/bash --uid "${USER_UID}" --gid "${USER_GID}" -m "${USERNAME}"; \
    fi; \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-${USERNAME}; \
    chmod 0440 /etc/sudoers.d/99-${USERNAME}

# Устанавливаем uv и кладем бинарь в /usr/local/bin (доступен всем пользователям)
RUN set -eux; \
    curl -fsSL https://astral.sh/uv/install.sh | sh; \
    UV_SRC="$(command -v /root/.local/bin/uv || true)"; \
    if [ -z "${UV_SRC}" ] || [ ! -x "${UV_SRC}" ]; then \
      echo "uv install failed" >&2; exit 1; \
    fi; \
    cp -f "${UV_SRC}" /usr/local/bin/uv; \
    chmod 0755 /usr/local/bin/uv; \
    uv --version

# Гарантируем доступность uv в PATH для всех пользователей
ENV PATH="/usr/local/bin:${PATH}"

# По умолчанию рабочая директория в /workspaces
WORKDIR /workspaces

# По желанию: ускорение pip колеса torch через индекс CPU как в pyproject
ENV UV_LINK_MODE=copy

# Прописываем локаль (опционально, для удобства терминала)
RUN apt-get update && apt-get install -y --no-install-recommends locales && rm -rf /var/lib/apt/lists/* \
    && sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# В контейнере будем использовать системный python3 как базу; venv создаст postCreate.sh
CMD ["bash"]


