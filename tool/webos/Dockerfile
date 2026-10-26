# Ubuntu toolchain for building Soup's webOS IPK with LG's flutter-webOS,
# trimmed from https://github.com/lg-flutter-webos/devcontainer. Used by
# `task v2:webos:build`; the repo is bind-mounted at /soup.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    ca-certificates clang cmake curl file git git-lfs gnupg libgtk-3-0 \
    libgtk-3-dev liblzma-dev libstdc++-10-dev make ninja-build pkg-config \
    python3 unzip wget xz-utils \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Match the host user so build output in the bind mount stays theirs.
ARG USER_UID=1000
ARG USER_GID=1000
RUN groupadd --gid ${USER_GID} soup 2>/dev/null || true; \
    useradd -m --uid ${USER_UID} --gid ${USER_GID} soup \
    && mkdir -p /opt/webos-ndk && chown soup /opt/webos-ndk
USER soup
WORKDIR /home/soup

ENV NPM_CONFIG_PREFIX=/home/soup/.npm-global \
    PATH=/home/soup/.npm-global/bin:/home/soup/flutter-webos/bin:$PATH

# ares (webOS CLI) packages and installs the IPK.
RUN npm install -g @webos-tools/cli && ares -V

ARG FLUTTER_WEBOS_REF=950398131830e9bd5dc91e588c3db8f5c42322be
RUN git clone https://github.com/lg-flutter-webos/flutter-webos.git \
    && git -C flutter-webos checkout ${FLUTTER_WEBOS_REF}

# The webOS NDK is under LG's SDK License Agreement. Its installer only runs
# non-interactively (-y) when the person building passes
# WEBOS_NDK_ACCEPT_EULA=1; it is a build arg, never baked into the image.
ARG WEBOS_NDK_VERSION=11.2.0
ARG WEBOS_NDK_ACCEPT_EULA
RUN if [ "${WEBOS_NDK_ACCEPT_EULA}" != "1" ]; then \
      echo "The webOS NDK is licensed under LG's SDK License Agreement."; \
      echo "Review it, then rerun with WEBOS_NDK_ACCEPT_EULA=1 to accept."; \
      exit 1; \
    fi \
    && installer=webos-ndk-flutter-starfish-x86_64-ca9v1-${WEBOS_NDK_VERSION}.sh \
    && wget -q https://github.com/lg-flutter-webos/ndk/releases/download/${WEBOS_NDK_VERSION}/$installer \
    && chmod +x $installer \
    && ./$installer -y -d /opt/webos-ndk \
    && rm $installer \
    && ln -s "$(ls /opt/webos-ndk/environment-setup-*)" /opt/webos-ndk/env-setup

ENV WEBOS_FLUTTER_NDK_ENV=/opt/webos-ndk/env-setup

RUN flutter-webos precache -f && flutter-webos config --enable-custom-devices

# Registered TVs and their SSH keys persist in volumes mounted here; create
# them as the user so the volumes aren't root-owned.
RUN mkdir -p /home/soup/.config /home/soup/.ssh /home/soup/.webos && chmod 700 /home/soup/.ssh

# flutter-webos detects TVs with `ping`.
USER root
RUN apt-get update && apt-get install -y iputils-ping \
    && rm -rf /var/lib/apt/lists/*
USER soup

WORKDIR /soup/apps/android-v2
