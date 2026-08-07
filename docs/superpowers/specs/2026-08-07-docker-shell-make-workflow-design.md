# Docker Shell Make Workflow Design

## Goal

Provide the same top-level workflow used by OS-Course-Lab while preserving
ChCore's existing build implementation:

```sh
make
make qemu
```

The primary use case is an interactive Docker shell opened at the repository
root. The same commands must also remain usable on the ARM64 macOS host, where
`chbuild` transparently starts its normal temporary toolchain container.

## Scope

This change adds a root-level GNU Make interface over the existing `chbuild`
commands. It does not replace CMake, duplicate QEMU arguments, introduce a
persistent build container, or change the recipe-derived Docker image naming
scheme.

Raspi3 remains the only supported QEMU platform in this workflow.

## Command Interface

The root `Makefile` will expose these phony targets:

- `all`: the default target and an alias for `build`.
- `defconfig`: run `./chbuild defconfig raspi3` explicitly.
- `build`: create the Raspi3 default configuration only when `.config` is
  absent, then run `./chbuild build`.
- `qemu`: depend on `build`, then run `./chbuild run`. This means every
  invocation performs an incremental full build before entering QEMU.
- `clean`: run `./chbuild clean` and retain `.config`.
- `distclean`: run `./chbuild distclean` and remove `.config`.
- `help`: print the supported Make targets and their behavior.

`CHBUILD` and `PLATFORM` will be overridable Make variables with defaults of
`./chbuild` and `raspi3`. `qemu` remains restricted by `chbuild run`, which
rejects non-Raspi3 configurations with its existing diagnostic.

## Execution Model

The Makefile delegates every operation to `chbuild` rather than invoking CMake
or QEMU directly.

Inside a Docker or dev-container shell, `chbuild` detects `/.dockerenv` and
executes its requested function in the current container. It does not start a
nested container. Source files, `.config`, and `build/` therefore remain in the
repository bind mount.

On the ARM64 host, Make invokes the same `chbuild` commands. The existing
`chbuild` host path checks or builds the recipe-derived `linux/arm64` image,
bind-mounts the repository, runs as the host UID/GID, and removes the temporary
container afterward.

`make qemu` follows this exact sequence:

1. If `.config` is absent, run `./chbuild defconfig raspi3`.
2. Run `./chbuild build` for an incremental full build.
3. Run `./chbuild run`, which executes the generated `build/simulate.sh`.
4. Propagate build or QEMU failures as the Make exit status.

The generated simulation script remains the sole owner of QEMU machine
arguments, logging, and GDB port selection.

## Docker Shell Entry

Documentation will show an interactive shell using the canonical
recipe-derived image name:

```sh
./chbuild prepare-image
chcore_image=$(./chbuild image)
docker run --rm -it \
  --platform linux/arm64 \
  -u "$(id -u):$(id -g)" \
  -v "$PWD:$PWD" \
  -w "$PWD" \
  "$chcore_image" \
  bash
```

The documentation will also explain that a local alias such as
`chcore-dev:arm64` may be substituted for convenience, but the canonical image
name from `./chbuild image` is the portable default. `./chbuild prepare-image`
creates the exact current image without configuring or building ChCore; `make`
creates `.config` when it is absent.

## Approved Final Review Correction

`prepare-image` is a local `chbuild` command that reuses the existing
recipe-derived `linux/arm64` image preparation path. The Make prerequisite is
the literal `.config`, because `chbuild` hardcodes that path; only `CHBUILD`
and `PLATFORM` are supported Make overrides.

No Docker shell management script is added in this change. Container creation
remains an explicit Docker command or a dev-container operation.

## Error Handling

- If automatic default configuration fails, Make stops before building.
- If the build fails, `make qemu` stops and does not start QEMU.
- If `build/simulate.sh` is missing after the build, `chbuild run` supplies its
  existing error and Make returns failure.
- If the configured platform is not Raspi3, `chbuild run` supplies its existing
  unsupported-platform error.
- Docker availability, host architecture, image preparation, and QEMU exit
  status continue to be validated by `chbuild`.

## Testing

A shell regression test will run the root Makefile against a fake `chbuild`
executable in an isolated temporary directory. It will verify:

1. Fresh `make` invokes `defconfig raspi3` followed by `build`.
2. Repeated `make` with `.config` present invokes only `build`.
3. Fresh `make qemu` invokes `defconfig raspi3`, `build`, and `run` in order.
4. A failing build prevents `run` from being invoked and is returned as a Make
   failure.
5. `clean` and `distclean` delegate to the matching `chbuild` commands.

The existing `tests/chbuild_arm64_test.sh` remains unchanged and will also be
run to ensure the Docker wrapper behavior is not regressed. A real build will
verify that `make` generates `build/kernel.img` and `build/simulate.sh`. A
bounded QEMU smoke test will verify visible ChCore boot output without leaving
an interactive QEMU process behind.

## Documentation

`README.md` will gain a concise Docker-shell section containing:

- how to resolve the canonical recipe-derived image;
- how to open a correctly mounted ARM64 shell;
- `make` for an incremental full build;
- `make qemu` for build-and-boot;
- `Ctrl-a x` for leaving interactive QEMU; and
- the corresponding clean targets.

The existing `./chbuild` commands remain documented and supported.
