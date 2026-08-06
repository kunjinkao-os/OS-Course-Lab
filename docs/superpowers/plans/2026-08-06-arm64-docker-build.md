# Native ARM64 Docker Build and Headless QEMU Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build ChCore in a native `linux/arm64` container on Apple Silicon and boot the Raspi3 result through an interactive, headless QEMU session using `./chbuild run`.

**Architecture:** A repository-owned Ubuntu 20.04 ARM64 image supplies the GCC 9 AArch64 cross toolchain, CMake, Clang-Tidy 16, QEMU, and a compatible implementation of the image-only `read_procmgr_elf_tool`. The ARM64 base manifest is pinned by digest and the downloaded LLVM signing key is checked by SHA-256. `chbuild` derives a local cache tag from the Dockerfile, helper, and `.dockerignore`, builds the image on first use, and runs every existing build command plus `run` in the cached image. The generated `build/simulate.sh` remains the sole owner of QEMU machine arguments and propagates QEMU failures through its logging pipeline.

**Tech Stack:** Bash 3.2-compatible shell, Docker/BuildKit, Ubuntu 20.04 ARM64, GCC 9 AArch64 cross compiler, CMake 3.16, Clang-Tidy 16 from apt.llvm.org, Python 3 with pyelftools, QEMU system emulator.

## Global Constraints

- The host target is Apple Silicon macOS and the final build container must report `aarch64`.
- Docker build and run operations must explicitly select `linux/arm64`; no amd64 emulation fallback is added.
- Existing `./chbuild defconfig`, `config`, `menuconfig`, `build`, `clean`, and `distclean` command syntax must remain valid.
- QEMU support in this change is limited to Raspi3 and must use the generated `build/simulate.sh` with `-nographic -serial mon:stdio`.
- QEMU remains interactive and exits with `Ctrl-a x`.
- The toolchain image is local-only; this work does not publish to an external registry.
- Shell code must run with the Bash 3.2 shipped by macOS.
- The image tag is recipe-derived, not a content address for resolved image
  layers; unversioned APT packages may change as repositories change.
- Fully pinned APT versions or immutable package snapshots are out of scope.

---

## File Structure

- Create `scripts/docker/arm64/Dockerfile`: canonical native ARM64 build and QEMU environment.
- Create `scripts/docker/arm64/read_procmgr_elf_tool.py`: portable replacement for the amd64-only helper embedded in `ipads/oslab:24.09`.
- Create `.dockerignore`: keep the 285 MB source tree out of the toolchain image build context while allowing the Dockerfile helper input.
- Create `tests/chbuild_arm64_test.sh`: host-side regression tests for help text, recipe-derived tag inputs, platform checks, Docker image preparation, and run invocation.
- Create `tests/qemu_emulate_test.sh`: generated-script behavior test for QEMU failure propagation and `build/exec_log` ownership.
- Modify `chbuild`: recipe-derived local image preparation, exact image-name diagnostics, native ARM64 container execution, and the new `run` command.
- Modify `scripts/qemu/emulate.tpl.sh`: propagate QEMU pipeline failures and keep QEMU logs in `build/`.
- Modify `.devcontainer/devcontainer.json`: point VS Code directly at the canonical ARM64 Dockerfile and platform.
- Delete `.devcontainer/Dockerfile`: remove the obsolete wrapper around the amd64-only upstream image.
- Modify `README.md`: document Apple Silicon prerequisites and the build/run workflow.

### Task 1: Add the ARM64 Toolchain Image

**Files:**
- Create: `.dockerignore`
- Create: `scripts/docker/arm64/Dockerfile`
- Create: `scripts/docker/arm64/read_procmgr_elf_tool.py`
- Create: `tests/read_procmgr_elf_tool_test.py`

**Interfaces:**
- Consumes: repository-root Docker build context and Docker automatic `TARGETARCH` argument.
- Produces: an ARM64 image containing `aarch64-linux-gnu-gcc`, `cmake`, `ccmake`, `cpio`, Clang-Tidy 16 as `clang-tidy`, `read_procmgr_elf_tool`, and `qemu-system-aarch64` on `PATH`; user `stu` for dev-container use.

- [ ] **Step 1: Add the metadata-tool implementation test fixture behavior to the script**

Create `scripts/docker/arm64/read_procmgr_elf_tool.py` with the exact output contract used by `kernel/object/thread_env.h`: six big-endian 64-bit metadata values followed by three native little-endian ELF64 program headers.

```python
#!/usr/bin/env python3
"""Generate the metadata prefix expected before the ChCore procmgr ELF."""

import struct
import sys
from typing import NoReturn

from elftools.common.exceptions import ELFError
from elftools.elf.enums import ENUM_P_TYPE_BASE
from elftools.elf.elffile import ELFFile


def fail(message: str) -> NoReturn:
    print(f"read_procmgr_elf_tool: {message}", file=sys.stderr)
    raise SystemExit(1)


def numeric_program_type(value) -> int:
    if isinstance(value, int):
        return value
    mapped_value = ENUM_P_TYPE_BASE.get(value)
    if isinstance(mapped_value, int):
        return mapped_value
    for number, name in ENUM_P_TYPE_BASE.items():
        if isinstance(number, int) and name == value:
            return number
    fail(f"unsupported program header type: {value}")


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: read_procmgr_elf_tool <procmgr.elf>")

    try:
        with open(sys.argv[1], "rb") as stream:
            elf = ELFFile(stream)
            headers = list(elf.iter_segments())
            if elf.elfclass != 64 or not elf.little_endian:
                fail("procmgr must be a little-endian ELF64 file")
            if len(headers) != 3:
                fail(f"expected 3 program headers, found {len(headers)}")

            memory_size = sum(
                segment["p_memsz"]
                for segment in headers
                if segment["p_type"] == "PT_LOAD"
            )
            metadata = struct.pack(
                ">6Q",
                memory_size,
                elf.header["e_entry"],
                elf.header["e_flags"],
                elf.header["e_phentsize"],
                elf.header["e_phnum"],
                headers[0]["p_vaddr"] + elf.header["e_phoff"],
            )
            program_headers = b"".join(
                struct.pack(
                    "<II6Q",
                    numeric_program_type(segment["p_type"]),
                    segment["p_flags"],
                    segment["p_offset"],
                    segment["p_vaddr"],
                    segment["p_paddr"],
                    segment["p_filesz"],
                    segment["p_memsz"],
                    segment["p_align"],
                )
                for segment in headers
            )
    except (ELFError, OSError, KeyError, struct.error, ValueError) as error:
        fail(str(error))

    with open("elf_info.temp", "wb") as output:
        output.write(metadata)
        output.write(program_headers)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Verify the helper parses before adding the image**

Run:

```sh
python3 -c 'import ast, pathlib; ast.parse(pathlib.Path("scripts/docker/arm64/read_procmgr_elf_tool.py").read_text())'
```

Expected: exit status 0 and no output. This check does not import pyelftools, so it is valid on the macOS host.

- [ ] **Step 2a: Verify both pyelftools enum directions without pyelftools installed**

Create `tests/read_procmgr_elf_tool_test.py`. Load the helper through
`importlib` while stubbing its `elftools` imports in `sys.modules`, then verify
that `numeric_program_type()` accepts an integer value, a string-to-integer
enum mapping (the Ubuntu Focal pyelftools 0.26 representation), and an
integer-to-string mapping. Verify an unknown string exits through `fail()`.

Run:

```sh
python3 -m unittest discover -s tests -p 'read_procmgr_elf_tool_test.py'
```

Expected: four tests pass without requiring pyelftools on the host.

- [ ] **Step 3: Add the ARM64 Dockerfile**

Create `scripts/docker/arm64/Dockerfile`:

```dockerfile
FROM ubuntu:20.04@sha256:722ea796ac2d57eeb3627c58a582fc1acc58be51faf815e1bce1682ae5c092f7

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
    && printf '%s  %s\n' \
        '8b2a587ffd672c4687e7581dad4b2f6c1bb2ad6b480cd9771ba2ff48e0b8c75d' \
        /tmp/llvm-snapshot.gpg.key \
        | sha256sum --check --strict - \
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
```

Ubuntu 20.04 is deliberate: it matches the upstream `ipads/oslab:24.09` base and provides GCC 9.3 and CMake 3.16 on ARM64. The digest is the official `linux/arm64/v8` manifest resolved for `ubuntu:20.04`; the LLVM key digest is checked before `gpg --dearmor`. Clang-Tidy 16 comes from apt.llvm.org because the distro's Clang-Tidy 10 does not support the project's `--config-file` option. Distribution QEMU is sufficient because `scripts/qemu/qemu_wrapper.sh` already translates `raspi3b` to the older `raspi3` machine name for QEMU versions below 6.2. APT package versions remain repository-resolved and therefore are not fully reproducible.

- [ ] **Step 4: Run static Dockerfile checks**

Create a root `.dockerignore` that allows only the two ARM64 image inputs through the build context:

```dockerignore
**
!scripts/
!scripts/docker/
!scripts/docker/arm64/
!scripts/docker/arm64/Dockerfile
!scripts/docker/arm64/read_procmgr_elf_tool.py
```

Then run:

```sh
rg -n 'FROM ubuntu:20\.04@sha256:722ea796|8b2a587ffd672c46|TARGETARCH|apt\.llvm\.org/focal|llvm-toolchain-focal-16|clang-tidy-16|python3-pyelftools|qemu-system-arm|gcc-aarch64-linux-gnu' scripts/docker/arm64/Dockerfile
```

Expected: each required base/platform/tool dependency is present.

- [ ] **Step 5: Commit the image unit**

```sh
git add .dockerignore scripts/docker/arm64/Dockerfile \
    scripts/docker/arm64/read_procmgr_elf_tool.py
git commit -m "build: add native arm64 toolchain image"
```

### Task 2: Make `chbuild` Prepare and Use the ARM64 Image

**Files:**
- Create: `tests/chbuild_arm64_test.sh`
- Modify: `chbuild`

**Interfaces:**
- Consumes: `scripts/docker/arm64/Dockerfile`, `scripts/docker/arm64/read_procmgr_elf_tool.py`, `.dockerignore`, `docker`, `uname -m`, existing command functions, `.config`, and generated `build/simulate.sh`.
- Produces: `_docker_image_name`, `_prepare_docker_image`, `_docker_run`, public `image`, and public `run`; Docker invocations explicitly target `linux/arm64`.

- [ ] **Step 1: Write a failing host-orchestration test**

Create `tests/chbuild_arm64_test.sh`. It must create a temporary fake `docker` and `uname`, restore the environment on exit, and assert:

```bash
#!/bin/bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_dir"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

real_path=$PATH
export DOCKER_LOG="$tmp_dir/docker.log"

cat >"$tmp_dir/uname" <<'EOF'
#!/bin/bash
printf '%s\n' "${FAKE_UNAME:-arm64}"
EOF

cat >"$tmp_dir/docker" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$DOCKER_LOG"
if [ "$1" = image ] && [ "$2" = inspect ]; then
    exit "${FAKE_IMAGE_INSPECT_STATUS:-1}"
fi
exit 0
EOF

chmod +x "$tmp_dir/uname" "$tmp_dir/docker"
export PATH="$tmp_dir:$real_path"

help_output=$("$repo_dir/chbuild" --help)
grep -F 'run' <<<"$help_output" >/dev/null
grep -F 'image' <<<"$help_output" >/dev/null
grep -F 'linux/arm64' <<<"$help_output" >/dev/null

image_name=$("$repo_dir/chbuild" image)
[[ "$image_name" =~ ^chcore-build:arm64-[0-9a-f]{12}$ ]]

: >"$DOCKER_LOG"
"$repo_dir/chbuild" build
grep -E '^info$' "$DOCKER_LOG" >/dev/null
grep -E '^image inspect chcore-build:arm64-[0-9a-f]{12}$' "$DOCKER_LOG" >/dev/null
grep -E '^build --platform linux/arm64 .* -f .*scripts/docker/arm64/Dockerfile .*$' "$DOCKER_LOG" >/dev/null
grep -E '^run .*--platform linux/arm64 .*chcore-build:arm64-[0-9a-f]{12} .*chbuild build$' "$DOCKER_LOG" >/dev/null

: >"$DOCKER_LOG"
FAKE_IMAGE_INSPECT_STATUS=0 "$repo_dir/chbuild" build
if grep -E '^build ' "$DOCKER_LOG" >/dev/null; then
    echo "cached image unexpectedly rebuilt" >&2
    exit 1
fi

if FAKE_UNAME=x86_64 "$repo_dir/chbuild" build >"$tmp_dir/out" 2>&1; then
    echo "x86_64 host unexpectedly accepted" >&2
    exit 1
fi
grep -F 'requires an ARM64 host' "$tmp_dir/out" >/dev/null

echo "chbuild ARM64 tests passed"
```

Use `cat` only in this plan's illustrative test setup; during implementation, create the file through the repository patching mechanism. The here-documents are runtime fixture generation, not repository file edits.

- [ ] **Step 2: Run the test and confirm the expected failure**

Run:

```sh
bash tests/chbuild_arm64_test.sh
```

Expected: FAIL because help does not mention `run`/`image`/`linux/arm64` and `chbuild` still invokes `ipads/oslab:24.09`.

- [ ] **Step 3: Add Docker constants and recipe-derived image helpers**

Near the current Docker settings in `chbuild`, define:

```bash
docker_platform="linux/arm64"
dockerfile="scripts/docker/arm64/Dockerfile"
docker_helper="scripts/docker/arm64/read_procmgr_elf_tool.py"
dockerignore=".dockerignore"
docker_image_repository="chcore-build"
```

Add Bash 3.2-compatible helpers before `_docker_run`:

```bash
_docker_inputs_sha256() {
    local input_hashes digest_line
    if command -v sha256sum >/dev/null 2>&1; then
        input_hashes=$(sha256sum \
            "$dockerfile" "$docker_helper" "$dockerignore") || {
            _echo_err "Cannot hash Docker image inputs" >&2
            return 1
        }
        digest_line=$(sha256sum <<<"$input_hashes") || {
            _echo_err "Cannot hash Docker image inputs" >&2
            return 1
        }
    elif command -v shasum >/dev/null 2>&1; then
        input_hashes=$(shasum -a 256 \
            "$dockerfile" "$docker_helper" "$dockerignore") || {
            _echo_err "Cannot hash Docker image inputs" >&2
            return 1
        }
        digest_line=$(shasum -a 256 <<<"$input_hashes") || {
            _echo_err "Cannot hash Docker image inputs" >&2
            return 1
        }
    else
        _echo_err "Cannot hash Docker image inputs: install sha256sum or shasum" >&2
        return 1
    fi
    printf '%s\n' "${digest_line%% *}"
}

_docker_image_name() {
    local digest
    digest=$(_docker_inputs_sha256) || return 1
    printf '%s:arm64-%s\n' "$docker_image_repository" "${digest:0:12}"
}

_check_arm64_host() {
    case "$(uname -m)" in
    arm64 | aarch64) ;;
    *)
        _echo_err "Native $docker_platform build requires an ARM64 host" >&2
        return 1
        ;;
    esac
}

_prepare_docker_image() {
    local image
    command -v docker >/dev/null 2>&1 || {
        _echo_err "Docker is not installed or is not on PATH" >&2
        return 1
    }
    _check_arm64_host || return 1
    docker info >/dev/null 2>&1 || {
        _echo_err "Docker daemon is unavailable; start Docker Desktop or OrbStack" >&2
        return 1
    }
    [ -f "$dockerfile" ] && [ -f "$docker_helper" ] \
        && [ -f "$dockerignore" ] || {
        _echo_err "Docker image recipe inputs are missing" >&2
        return 1
    }
    image=$(_docker_image_name) || return 1
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        _echo_info "Building native ARM64 toolchain image $image..." >&2
        docker build --platform "$docker_platform" \
            -t "$image" -f "$dockerfile" . >&2 || return 1
    fi
    printf '%s\n' "$image"
}
```

Because `_prepare_docker_image` is used in command substitution, send informational build text to stderr (for example `_echo_info ... >&2`) so stdout contains only the image name.

- [ ] **Step 4: Replace `_docker_run` with argument-safe ARM64 execution**

Replace the old fixed-image body with:

```bash
_docker_run() {
    if [ -f /.dockerenv ]; then
        "$@"
        return
    fi

    local image use_cgroup
    local -a docker_args
    image=$(_prepare_docker_image) || return 1
    use_cgroup=""
    if [[ ${CI_RUNNER_TAGS:-} =~ .*need_cgroup.* ]]; then
        use_cgroup="--cgroup-parent=$docker_cgroup"
    fi

    docker_args=(run -i --rm --init --platform "$docker_platform")
    [ -t 1 ] && docker_args+=(-t)
    [ -n "$use_cgroup" ] && docker_args+=("$use_cgroup")
    docker_args+=(
        -u "$(id -u):$(id -g)"
        -v "$PWD:$PWD"
        -w "$PWD"
        "$image"
        "$self"
    )
    docker "${docker_args[@]}" "$@"
}
```

Do not use `${variable,,}`, associative arrays, `mapfile`, or `readlink -f`; those are unavailable in macOS Bash 3.2.

- [ ] **Step 5: Add public `image` and `run` commands and help text**

Add:

```bash
run() {
    _check_config_file
    if ! grep -q '^CHCORE_PLAT:STRING=raspi3$' "$config_file"; then
        _echo_err "QEMU run currently supports only the raspi3 configuration"
        return 1
    fi
    if [ ! -x "$cmake_build_dir/simulate.sh" ]; then
        _echo_err "Missing $cmake_build_dir/simulate.sh; run '$self build' first"
        return 1
    fi
    exec "$cmake_build_dir/simulate.sh"
}

image() {
    _docker_image_name
}
```

Extend help with:

```text
    image                       print the exact recipe-derived local image name
    run                         boot a raspi3 build in QEMU (linux/arm64, -nographic)
```

Dispatch `image` locally before the generic Docker-command case. Also update the options introduction to state that Docker commands use a native `linux/arm64` image built on first use.

- [ ] **Step 6: Run shell tests**

Run:

```sh
bash -n chbuild
bash -n tests/chbuild_arm64_test.sh
bash tests/chbuild_arm64_test.sh
```

Expected: all commands exit 0; the last prints `chbuild ARM64 tests passed`.

- [ ] **Step 7: Commit the command unit**

```sh
git add chbuild tests/chbuild_arm64_test.sh
git commit -m "build: run chcore in native arm64 docker"
```

### Task 3: Unify the Dev Container and Document the Workflow

**Files:**
- Modify: `.devcontainer/devcontainer.json`
- Delete: `.devcontainer/Dockerfile`
- Modify: `README.md`

**Interfaces:**
- Consumes: canonical `scripts/docker/arm64/Dockerfile` and public `chbuild` commands.
- Produces: a dev-container definition and user documentation that use the same ARM64 toolchain path.

- [ ] **Step 1: Point the dev-container at the canonical Dockerfile**

Replace the build section in `.devcontainer/devcontainer.json` with:

```json
"build": {
  "dockerfile": "../scripts/docker/arm64/Dockerfile",
  "context": "..",
  "options": ["--platform=linux/arm64"]
},
```

Add `"--platform", "linux/arm64"` to `runArgs`, retain `remoteUser: "stu"`, and remove `.devcontainer/Dockerfile` so there is only one dependency definition.

- [ ] **Step 2: Rewrite the build/run portion of the README**

Document exactly:

````markdown
## Prerequisites (Apple Silicon)

- An Apple Silicon Mac (`arm64`)
- Docker Desktop, OrbStack, or another running Docker-compatible daemon

`chbuild` creates a local `linux/arm64` toolchain image on first use. The first
command downloads Ubuntu packages; later commands reuse the recipe-derived
local image tag and the normal Docker build cache. The tag covers the ARM64
Dockerfile, ELF helper, and `.dockerignore`. The base image is pinned by ARM64
digest and the LLVM signing key is verified by SHA-256, but unversioned APT
packages can change as the configured repositories change.

## Build and run

```sh
./chbuild defconfig raspi3
./chbuild build
./chbuild run
```

`./chbuild run` starts QEMU in `-nographic` mode and connects the ChCore serial
console to the terminal. Press `Ctrl-a x` to exit QEMU.

```sh
chcore_image=$(./chbuild image)
docker run --rm --platform linux/arm64 "$chcore_image" uname -m
```
````

Keep the existing `clean`, `--help`, coding-style, and debugging material. Add troubleshooting entries for a stopped daemon, a non-ARM host, and a missing `build/simulate.sh`.

- [ ] **Step 3: Validate configuration and documentation**

Run:

```sh
python3 -m json.tool .devcontainer/devcontainer.json >/dev/null
rg -n 'linux/arm64|./chbuild image|./chbuild run|recipe-derived|APT|Ctrl-a x|-nographic|Docker Desktop|OrbStack|aarch64' README.md
test ! -e .devcontainer/Dockerfile
git diff --check
```

Expected: JSON parsing succeeds, every workflow term is documented, the obsolete Dockerfile is absent, and Git reports no whitespace errors.

- [ ] **Step 4: Commit documentation and dev-container integration**

```sh
git add .devcontainer/devcontainer.json .devcontainer/Dockerfile README.md
git commit -m "docs: add Apple Silicon build and QEMU workflow"
```

### Task 4: Harden the Recipe and QEMU Failure Path

**Files:**
- Modify: `scripts/docker/arm64/Dockerfile`
- Modify: `scripts/qemu/emulate.tpl.sh`
- Modify: `chbuild`
- Modify: `tests/chbuild_arm64_test.sh`
- Create: `tests/qemu_emulate_test.sh`
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-08-06-arm64-docker-build-design.md`
- Modify: `docs/superpowers/plans/2026-08-06-arm64-docker-build.md`

**Interfaces:**
- Consumes: the official Ubuntu 20.04 `linux/arm64/v8` manifest digest, the
  downloaded apt.llvm.org signing-key bytes, and the canonical QEMU template.
- Produces: a pinned base, verified LLVM key, recipe-derived local tag,
  `./chbuild image`, and QEMU failure propagation through `tee`.

- [ ] **Step 1: Write focused failing regression tests**

Extend `tests/chbuild_arm64_test.sh` so `./chbuild image` returns one exact tag
without contacting Docker, changing each of the Dockerfile, helper, and
`.dockerignore` changes that tag, GNU `sha256sum` and macOS `shasum` produce the
same tag, and hash-command failures stop before Docker execution. Assert the
Dockerfile includes the resolved base and key digests.

Create `tests/qemu_emulate_test.sh`. Generate a temporary `simulate.sh` from
the canonical template, copy the real wrapper beside it, and place this fake
QEMU on `PATH`:

```bash
#!/bin/bash
if [ "${1:-}" = "--version" ]; then
    echo "QEMU emulator version 8.2.0"
    exit 0
fi
echo "fake qemu failure reached"
exit 37
```

Run the generated script from a separate working directory. Require status
37, require the marker in `build/exec_log`, and reject a working-directory
`exec_log`. This behavior test fails without `pipefail`; it is not a
string-only assertion.

- [ ] **Step 2: Pin and verify the recipe trust inputs**

Use these values, resolved from the official Ubuntu manifest and the current
official LLVM key download rather than guessed:

```dockerfile
FROM ubuntu:20.04@sha256:722ea796ac2d57eeb3627c58a582fc1acc58be51faf815e1bce1682ae5c092f7

# Immediately after downloading /tmp/llvm-snapshot.gpg.key:
RUN printf '%s  %s\n' \
        '8b2a587ffd672c4687e7581dad4b2f6c1bb2ad6b480cd9771ba2ff48e0b8c75d' \
        /tmp/llvm-snapshot.gpg.key \
        | sha256sum --check --strict -
```

In the actual Dockerfile the check remains in the existing `RUN` chain before
`gpg --dearmor`, so a mismatch stops the build.

- [ ] **Step 3: Propagate QEMU status and keep logs in `build/`**

Update only the canonical template's shell and logging behavior; do not take
ownership of generated machine or serial arguments:

```bash
set -eo pipefail

$basedir/../scripts/qemu/qemu_wrapper.sh \
    @qemu@ -gdb tcp::$port @qemu_options@ | tee "$basedir/exec_log"
```

- [ ] **Step 4: Complete exact recipe-tag and diagnostic behavior**

Hash the Dockerfile, helper, and `.dockerignore` through the Bash
3.2-compatible GNU/macOS branches shown in Task 2. Add a local `image` command:

```bash
image() {
    _docker_image_name
}
```

Dispatch it before generic Docker execution and document this reliable probe:

```sh
chcore_image=$(./chbuild image)
docker run --rm --platform linux/arm64 "$chcore_image" uname -m
```

Do not use `docker image ls | head`, which can select a stale recipe tag.

- [ ] **Step 5: Narrow the reproducibility claim and verify**

Describe the tag as a recipe-derived local cache tag. Document that the base
digest is pinned, the LLVM key is verified, and all three repository-owned
inputs enter the tag. Explicitly state that unversioned APT package resolution
can change with the repositories and immutable snapshots are out of scope.

Run:

```sh
bash -n chbuild
bash -n tests/chbuild_arm64_test.sh
bash -n tests/qemu_emulate_test.sh
bash tests/chbuild_arm64_test.sh
bash tests/qemu_emulate_test.sh
python3 -m unittest discover -s tests -p 'read_procmgr_elf_tool_test.py'
python3 -m json.tool .devcontainer/devcontainer.json >/dev/null
git diff --check
```

Expected: every command exits 0; the QEMU test proves that status 37
propagates and the ARM64 test reports all tag and hash checks passed.

### Task 5: Build and Boot ChCore End to End

**Files:**
- Verify only: `scripts/docker/arm64/Dockerfile`, `chbuild`, generated `.config`, and generated `build/`

**Interfaces:**
- Consumes: a running Docker daemon and network access for the first image build.
- Produces: a native ARM64 toolchain image, `build/kernel.img`, and visible ChCore serial output from headless QEMU.

- [ ] **Step 1: Run all static checks from a clean shell**

Run:

```sh
bash -n chbuild
bash -n tests/qemu_emulate_test.sh
bash tests/chbuild_arm64_test.sh
bash tests/qemu_emulate_test.sh
python3 -c 'import ast, pathlib; ast.parse(pathlib.Path("scripts/docker/arm64/read_procmgr_elf_tool.py").read_text())'
python3 -m unittest discover -s tests -p 'read_procmgr_elf_tool_test.py'
python3 -m json.tool .devcontainer/devcontainer.json >/dev/null
git diff --check
```

Expected: every command exits 0.

- [ ] **Step 2: Confirm Docker is available**

Run:

```sh
docker info
```

Expected: exit status 0. If it fails, start Docker Desktop or OrbStack and repeat; do not substitute an amd64 build.

- [ ] **Step 3: Build the recipe-derived local image and configure Raspi3**

If `.config` or `build/` exists from a prior incompatible build, run `./chbuild distclean` first. Then run:

```sh
./chbuild defconfig raspi3
```

Expected: the first invocation builds an image whose tag starts with `chcore-build:arm64-` and ends in exactly 12 hexadecimal digits, then reports `Default config written to .config file.`

- [ ] **Step 4: Verify native container architecture and required tools**

Resolve the image tag and run:

```sh
chcore_image=$(./chbuild image)
test -n "$chcore_image"
docker run --rm --platform linux/arm64 "$chcore_image" sh -c \
  'test "$(uname -m)" = aarch64 && command -v aarch64-linux-gnu-gcc && command -v clang-tidy && clang-tidy --version | grep -F "LLVM version 16." && command -v read_procmgr_elf_tool && command -v qemu-system-aarch64'
```

Expected: `uname -m` is `aarch64`, all commands resolve, `clang-tidy --version` reports LLVM 16, and the container exits 0.

- [ ] **Step 5: Complete the ChCore build**

Run:

```sh
./chbuild build
test -f build/kernel.img
test -x build/simulate.sh
grep -F -- '-nographic' build/simulate.sh
```

Expected: build exits 0, both artifacts exist, and the generated QEMU command includes `-nographic`.

- [ ] **Step 6: Boot and inspect serial output**

Run in an interactive terminal:

```sh
./chbuild run
```

Expected: QEMU starts with the Raspi3 machine, the terminal displays ChCore initialization messages such as `[ChCore] uart init finished`, and no graphical window opens. Press `Ctrl-a x`; the command returns to the host terminal.

- [ ] **Step 7: Record final verification state**

Run:

```sh
git status --short
git log -8 --oneline
```

Expected: only intended ignored/generated artifacts exist outside Git, and the final hardening commit is at the branch tip.
