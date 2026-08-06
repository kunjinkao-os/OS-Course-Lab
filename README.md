# IPADS ChCore MicroKernel Repository

## Prerequisites (Apple Silicon)

- An Apple Silicon Mac (`arm64`)
- Docker Desktop, OrbStack, or another running Docker-compatible daemon

`chbuild` creates a local `linux/arm64` toolchain image on first use. The first
command downloads Ubuntu packages; later commands reuse the recipe-derived
local image tag and the normal Docker build cache. The recipe tag covers the
ARM64 Dockerfile, the ELF helper, and `.dockerignore`. The Ubuntu ARM64 base is
pinned by digest, and the downloaded LLVM signing key is verified by SHA-256.

The image is not a fully reproducible package snapshot: unversioned APT
packages can resolve differently as the Ubuntu and LLVM repositories change.

完整中文教程请参阅 [ARM64 Docker 与 QEMU 使用指南](docs/arm64-docker-qemu-guide.md)。

## Build and run

```sh
./chbuild defconfig raspi3
./chbuild build
./chbuild run
```

`./chbuild run` starts QEMU in `-nographic` mode and connects the ChCore serial
console to the terminal. Press `Ctrl-a x` to exit QEMU.

To confirm that the exact image for the current recipe is ARM64, run:

```sh
chcore_image=$(./chbuild image)
docker run --rm --platform linux/arm64 "$chcore_image" uname -m
```

The expected output is `aarch64`. `./chbuild image` computes the current exact
local tag; it does not select an arbitrary older `arm64-*` tag.

## Troubleshooting

- If Docker reports that it cannot connect to the daemon, start Docker Desktop,
  OrbStack, or your Docker-compatible daemon, then rerun the command.
- This workflow requires an `arm64` host. On a non-ARM host, use a supported
  ARM64 environment before running `chbuild`.
- If `build/simulate.sh` is missing, first run `./chbuild defconfig raspi3` and
  `./chbuild build`; use `./chbuild run` rather than invoking the simulator
  directly.

## Additional `chbuild` commands

Clean and rebuild all:

```shell
./chbuild clean
./chbuild build
```

Full usage of `chbuild` script:

```shell
./chbuild --help
```

## Coding Style

Basic Requirements:

1. Please use #pragma once (instead of #ifndef) in header files.
2. Put all header files in kernel/include directory and, especially,
   put the architecture-dependent ones in kernel/include/arch/xxx/arch/
   (e.g., kernel/include/arch/aarch64/arch/) directory.

## Debugging

* `TRACE_SYSCALL` (disabled by default) in `user/chcore-libc/src/chcore-port/syscall_dispatcher.c` controls whether to print all syscall invocations in libc.
    Not all syscalls are printed. Exceptions include:
    1. SYS_sched_yield (generated too frequently);
    2. SYS_writev, SYS_ioctl and SYS_read (used in printf);
    3. SYS_io_submit (used in printf?).

* `kernel/include/common/debug.h` defines the kernel debugging options which can ease the procedure of bug hunting.

---
LICENSE: Relicensed under Mulan PSL v2.
