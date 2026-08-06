# Native ARM64 Docker Build and Headless QEMU Design

## Goal

Enable an Apple Silicon macOS host to build ChCore inside a native
`linux/arm64` Docker container and boot the resulting Raspi3 image with QEMU in
headless, interactive mode. The normal entry point remains `./chbuild`.

## Background

The existing `chbuild` script already runs build commands in
`ipads/oslab:24.09`, but that image is published only for `linux/amd64`.
Consequently, using it on Apple Silicon requires architecture emulation and
does not satisfy the native ARM64-container requirement. The existing Raspi3
QEMU configuration already generates `build/simulate.sh` with
`-nographic -serial mon:stdio`.

## Scope

This change will:

- provide a repository-owned `linux/arm64` toolchain image with a pinned ARM64
  base image and a verified LLVM repository signing key;
- make `chbuild` build and cache that image automatically;
- preserve the existing `defconfig`, `config`, `menuconfig`, `build`, `clean`,
  and `distclean` interfaces;
- add `./chbuild run` to boot a completed Raspi3 build with QEMU;
- keep QEMU attached to the terminal and use `-nographic` serial output;
- make the dev-container use the same toolchain definition; and
- document Apple Silicon setup, build, run, exit, and troubleshooting steps.

This change will not publish an image to an external registry, add an amd64
fallback, or add Raspi4 QEMU support. Raspi4 builds remain available, but
`./chbuild run` will reject a Raspi4 configuration with a clear error.

## Architecture

### ARM64 toolchain image

Add `scripts/docker/arm64/Dockerfile`, based on the Ubuntu 20.04 ARM64 manifest
pinned as `ubuntu:20.04@sha256:722ea796ac2d57eeb3627c58a582fc1acc58be51faf815e1bce1682ae5c092f7`.
It installs the AArch64 GNU cross compiler and binutils, C/C++ build tools,
CMake, the utilities referenced by the repository's build scripts, and
`qemu-system-aarch64` from the distribution packages. The apt.llvm.org signing
key is downloaded over HTTPS and checked against SHA-256
`8b2a587ffd672c4687e7581dad4b2f6c1bb2ad6b480cd9771ba2ff48e0b8c75d`
before it is converted into an APT keyring.

The image is a build environment, not a copy of the source tree. The repository
is bind-mounted at runtime so build outputs remain on the host and existing
incremental-build behavior is preserved.

### Image selection and caching

`chbuild` derives a local image tag from the content of three repository-owned
recipe inputs: `scripts/docker/arm64/Dockerfile`,
`scripts/docker/arm64/read_procmgr_elf_tool.py`, and `.dockerignore`. Before
running a container command, it checks that Docker is installed and the daemon
is reachable, then checks for that exact recipe-derived tag. If absent, it runs
a `docker build` targeting `linux/arm64`. Docker layer caching makes rebuilds
incremental, while the tag prevents silently reusing an image created from an
older version of any of those inputs.

This is a local recipe cache tag, not a content address for the built image.
Ubuntu and LLVM APT package versions and repository metadata are not pinned to
immutable snapshots, so a clean build of an unchanged recipe can resolve newer
package content under the same tag. Fully reproducible package resolution is
explicitly outside this change's scope.

The runtime invocation explicitly selects `--platform linux/arm64`, bind-mounts
the repository at the same absolute path, uses the repository as the working
directory, and maps the host UID and GID. It retains stdin and allocates a TTY
when the caller has one, so configuration menus and QEMU remain interactive.

### Command flow

The supported flow is:

```sh
./chbuild defconfig raspi3
./chbuild build
./chbuild run
```

For existing build commands, the host-side `chbuild` prepares the ARM64 image
and invokes itself in the container. Inside a container, the existing
`/.dockerenv` guard prevents recursion and executes the command directly.

`run` validates that `.config` selects Raspi3 and that `build/simulate.sh`
exists and is executable. It then executes that generated script in the same
ARM64 toolchain container. The generated script remains the single source of
truth for QEMU arguments and already includes `-nographic -serial mon:stdio`.
The user exits QEMU with `Ctrl-a x`.

### Dev-container

`.devcontainer/devcontainer.json` will reference the canonical ARM64 toolchain
Dockerfile rather than an `ipads/oslab:24.09` wrapper. The dev-container
configuration will explicitly target `linux/arm64`, keeping VS Code and
command-line builds on the same dependency set.

## Error Handling

`chbuild` will fail early with a specific message when:

- the Docker CLI is not installed;
- the Docker daemon is unavailable, including when Docker Desktop or OrbStack
  is stopped;
- the host is not ARM64 while the native-ARM64 path is selected;
- the toolchain image cannot be built;
- `.config` is missing or selects an unsupported platform for `run`; or
- `build/simulate.sh` is missing because the project has not been built.

Container and QEMU exit statuses propagate to the caller. The generated QEMU
script enables Bash `pipefail` so its logging pipeline returns a QEMU wrapper
failure, and writes both `exec_log` and `gdb-port` in `build/`. The generated
simulation script continues to own these behaviors and all QEMU arguments.

## Documentation

The README will state that this path targets Apple Silicon and requires a
running Docker Desktop, OrbStack, or compatible Docker daemon. It will document
the three-command build-and-run flow, the one-time image build, recipe-derived
local cache behavior and its APT-resolution limitation, `Ctrl-a x`, and a
diagnostic based on `./chbuild image` for confirming that the exact current
recipe image reports `aarch64`.

## Verification

Static verification consists of:

- parsing `chbuild` with `bash -n`;
- running the focused recipe-tag and QEMU failure-path shell tests;
- checking that `./chbuild --help` documents `run` and ARM64 behavior; and
- reviewing the generated Docker build command for an explicit
  `linux/arm64` platform.

Dynamic verification, with a running Docker daemon, consists of:

1. Building the toolchain image from a clean local image state.
2. Resolving the image with `chcore_image=$(./chbuild image)`, running
   `uname -m` in that exact image, and requiring `aarch64`.
3. Running `./chbuild defconfig raspi3`.
4. Running a complete `./chbuild build` and requiring a successful exit.
5. Running `./chbuild run`, confirming the QEMU command uses `-nographic`, and
   observing ChCore initialization output on the terminal.
6. Exiting QEMU with `Ctrl-a x` and confirming control returns to the host.

Dynamic verification requires a running Docker Desktop, OrbStack, or compatible
daemon. Static checks remain available when the daemon is stopped.
