FROM ubuntu:20.04

ARG TARGETARCH
ARG USERNAME=stu
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

RUN test "${TARGETARCH}" = "arm64"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        gnupg \
        wget \
    && wget -q -O /tmp/llvm-snapshot.gpg.key \
        https://apt.llvm.org/llvm-snapshot.gpg.key \
    && gpg --dearmor --output /usr/share/keyrings/llvm-archive-keyring.gpg \
        /tmp/llvm-snapshot.gpg.key \
    && printf '%s\n' \
        'deb [signed-by=/usr/share/keyrings/llvm-archive-keyring.gpg] http://apt.llvm.org/focal/ llvm-toolchain-focal-16 main' \
        > /etc/apt/sources.list.d/llvm-16.list \
    && rm /tmp/llvm-snapshot.gpg.key \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        binutils-aarch64-linux-gnu \
        clang-tidy-16 \
        cmake \
        cmake-curses-gui \
        cpio \
        g++ \
        g++-aarch64-linux-gnu \
        gcc \
        gcc-aarch64-linux-gnu \
        git \
        make \
        ninja-build \
        patch \
        pkg-config \
        python3 \
        python3-pyelftools \
        qemu-system-arm \
        sudo \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/docker/arm64/read_procmgr_elf_tool.py \
    /usr/local/bin/read_procmgr_elf_tool

RUN chmod 0755 /usr/local/bin/read_procmgr_elf_tool \
    && ln -s /usr/bin/clang-tidy-16 /usr/local/bin/clang-tidy \
    && ln -s /usr/bin/make /usr/local/bin/gmake \
    && groupadd --gid "${USER_GID}" "${USERNAME}" \
    && useradd --uid "${USER_UID}" --gid "${USER_GID}" \
        --create-home --shell /bin/bash "${USERNAME}" \
    && usermod -aG sudo "${USERNAME}" \
    && passwd -d "${USERNAME}"

CMD ["/bin/bash"]
