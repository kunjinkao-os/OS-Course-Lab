# Docker Shell Make Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a repository-root `make` build and `make qemu` build-and-boot workflow that works naturally inside the ARM64 Docker shell and remains compatible with host-side `chbuild` automation.

**Architecture:** A small root `Makefile` is a stable user-facing adapter over `chbuild`; it never duplicates CMake or QEMU implementation details. A hermetic shell regression test substitutes a fake `chbuild` to verify target ordering and failure propagation, while README instructions show how to open the existing recipe-derived toolchain image as a correctly mounted interactive shell.

**Tech Stack:** GNU Make, Bash, existing `chbuild`, CMake, Docker `linux/arm64`, QEMU Raspi3

## Approved Final Review Correction

The Docker-shell entry must call `./chbuild prepare-image` before resolving
`./chbuild image`, so it works with an absent `.config` or a pruned image.
The root Makefile uses a literal `.config` prerequisite because `chbuild`
hardcodes that path; only `CHBUILD` and `PLATFORM` are supported overrides.

## Global Constraints

- The default platform is exactly `raspi3`; `chbuild run` remains the authority that rejects unsupported QEMU platforms.
- `make` must automatically create `.config` with `./chbuild defconfig raspi3` only when `.config` is absent, then perform a full incremental build.
- `make qemu` must run the complete `make` build path before `./chbuild run` on every invocation.
- The Makefile must delegate build and QEMU behavior to `chbuild`; it must not duplicate CMake flags, QEMU arguments, logging, image preparation, or Docker nesting detection.
- The existing recipe-derived canonical image naming and `linux/arm64` requirement must remain unchanged.
- The workflow must work both inside a Docker/dev-container shell and from the ARM64 host.
- Existing user changes under `user/system-services/chcore-libc/musl-libc/` and unrelated untracked files must not be staged or modified.

---

### Task 1: Add the tested root Make interface

**Files:**
- Create: `Makefile`
- Create: `tests/make_workflow_test.sh`

**Interfaces:**
- Consumes: `./chbuild defconfig <platform>`, `./chbuild build`, `./chbuild run`, `./chbuild clean`, and `./chbuild distclean`.
- Produces: phony Make targets `all`, `defconfig`, `build`, `qemu`, `clean`, `distclean`, and `help`; overridable Make variables `CHBUILD` and `PLATFORM`.

- [ ] **Step 1: Write the failing Make workflow regression test**

Create `tests/make_workflow_test.sh` with this complete content:

```bash
#!/bin/bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

work_dir="$tmp_dir/work"
export MAKE_WORKFLOW_LOG="$tmp_dir/make-workflow.log"

reset_fixture() {
    rm -rf "$work_dir"
    mkdir -p "$work_dir"
    cp "$repo_dir/Makefile" "$work_dir/Makefile"
    : >"$MAKE_WORKFLOW_LOG"

    cat >"$work_dir/chbuild" <<'EOF'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >>"$MAKE_WORKFLOW_LOG"
case "${1:-}" in
defconfig)
    : >.config
    ;;
build)
    if [ "${FAIL_BUILD:-0}" = 1 ]; then
        exit 23
    fi
    ;;
distclean)
    rm -f .config
    ;;
esac
EOF
    chmod +x "$work_dir/chbuild"
}

assert_log() {
    local expected="$tmp_dir/expected.log"
    printf '%s\n' "$@" >"$expected"
    diff -u "$expected" "$MAKE_WORKFLOW_LOG"
}

reset_fixture
make -s -C "$work_dir"
assert_log 'defconfig raspi3' 'build'

: >"$MAKE_WORKFLOW_LOG"
make -s -C "$work_dir"
assert_log 'build'

reset_fixture
make -s -C "$work_dir" qemu
assert_log 'defconfig raspi3' 'build' 'run'

reset_fixture
if FAIL_BUILD=1 make -s -C "$work_dir" qemu; then
    echo "make qemu unexpectedly ignored a build failure" >&2
    exit 1
fi
assert_log 'defconfig raspi3' 'build'

reset_fixture
make -s -C "$work_dir" clean
assert_log 'clean'

reset_fixture
make -s -C "$work_dir" defconfig PLATFORM=raspi4
assert_log 'defconfig raspi4'

reset_fixture
make -s -C "$work_dir" distclean
assert_log 'distclean'

help_output=$(make -s -C "$work_dir" help)
grep -F 'make qemu' <<<"$help_output" >/dev/null
grep -F 'make distclean' <<<"$help_output" >/dev/null

echo "Make workflow tests passed"
```

- [ ] **Step 2: Run the new test and verify it fails because the root Makefile is absent**

Run:

```bash
bash -n tests/make_workflow_test.sh
bash tests/make_workflow_test.sh
```

Expected: syntax validation passes, then the regression test fails with `cp: .../Makefile: No such file or directory`.

- [ ] **Step 3: Implement the minimal root Makefile**

Create `Makefile` with this complete content. Recipe lines must begin with literal tab characters.

```make
CHBUILD ?= ./chbuild
PLATFORM ?= raspi3

.DEFAULT_GOAL := all

.PHONY: all defconfig build qemu clean distclean help

all: build

defconfig:
	$(CHBUILD) defconfig $(PLATFORM)

.config:
	$(CHBUILD) defconfig $(PLATFORM)

build: .config
	$(CHBUILD) build

qemu: build
	$(CHBUILD) run

clean:
	$(CHBUILD) clean

distclean:
	$(CHBUILD) distclean

help:
	@printf '%s\n' \
		'make              configure Raspi3 if needed, then build ChCore' \
		'make qemu         build ChCore, then boot it in QEMU' \
		'make defconfig    generate the default config for PLATFORM (default: raspi3)' \
		'make clean        remove build output and retain .config' \
		'make distclean    remove build output and .config'
```

- [ ] **Step 4: Run focused tests and verify all Make behavior passes**

Run:

```bash
bash -n tests/make_workflow_test.sh
bash tests/make_workflow_test.sh
make -s help
```

Expected: the test prints `Make workflow tests passed`; help lists `make`, `make qemu`, `make defconfig`, `make clean`, and `make distclean`.

- [ ] **Step 5: Run existing wrapper regressions**

Run:

```bash
bash tests/chbuild_arm64_test.sh
bash tests/qemu_emulate_test.sh
python3 tests/read_procmgr_elf_tool_test.py
```

Expected: all three existing tests pass, including `chbuild ARM64 tests passed` and `QEMU emulate failure test passed`.

- [ ] **Step 6: Review and commit only the Make interface files**

Run:

```bash
git diff --check -- Makefile tests/make_workflow_test.sh
git status --short
git add Makefile tests/make_workflow_test.sh
git diff --cached --check
git commit -m "build: add docker shell make workflow"
```

Expected: the commit contains only `Makefile` and `tests/make_workflow_test.sh`; existing musl-libc and unrelated changes remain unstaged.

---

### Task 2: Document and validate the end-to-end Docker shell workflow

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: the Task 1 Make targets and the canonical image name printed by `./chbuild image`.
- Produces: a portable Docker shell command plus documented `make`, `make qemu`, cleanup, and QEMU-exit usage.

- [ ] **Step 1: Add the Docker shell and Make workflow documentation**

Insert the following section in `README.md` immediately after the existing `Build and run` section's `Ctrl-a x` paragraph and before the image architecture check:

````markdown
### Docker shell and Make workflow

To work in an interactive toolchain shell, first prepare the current recipe
image:

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

From the repository root inside that shell, build or build-and-boot with:

```sh
make
make qemu
```

`make` creates the default Raspi3 configuration when `.config` is absent and
then performs an incremental full build. `make qemu` always builds first and
then starts the generated QEMU launcher. Press `Ctrl-a x` to leave QEMU.

The same Make commands also work directly on an Apple Silicon host; in that
case `chbuild` starts the temporary ARM64 container automatically. A local
alias such as `chcore-dev:arm64` may replace `"$chcore_image"`, but the
recipe-derived name from `./chbuild image` is the portable source of truth.

Clean while retaining `.config`, or remove both build output and configuration:

```sh
make clean
make distclean
```
````

- [ ] **Step 2: Verify documentation syntax and required commands**

Run:

```bash
rg -n 'Docker shell and Make workflow|chcore_image=.*chbuild image|make qemu|make clean|make distclean|Ctrl-a x|linux/arm64' README.md
git diff --check -- README.md
```

Expected: every required workflow term is present and `git diff --check` prints nothing.

- [ ] **Step 3: Run the complete automated regression suite for this change**

Run:

```bash
bash tests/make_workflow_test.sh
bash tests/chbuild_arm64_test.sh
bash tests/qemu_emulate_test.sh
python3 tests/read_procmgr_elf_tool_test.py
```

Expected: all four commands exit zero.

- [ ] **Step 4: Perform a real Make build with the canonical image**

Run from the repository root:

```bash
make
test -s build/kernel.img
test -x build/simulate.sh
```

Expected: `make` exits zero, reports `Succeeded to build all targets`, and both artifact checks pass. If the user's pre-existing musl-libc edits cause a compiler error, record that separately and do not modify or discard those edits as part of this feature.

- [ ] **Step 5: Perform a bounded `make qemu` boot smoke test**

Run from the repository root:

```bash
chcore_image=$(./chbuild image)
set +e
docker run --rm -i \
  --platform linux/arm64 \
  -u "$(id -u):$(id -g)" \
  -v "$PWD:$PWD" \
  -w "$PWD" \
  "$chcore_image" \
  timeout 45s make qemu
smoke_status=$?
set -e
test "$smoke_status" -eq 124
rg -n '\[ChCore\] uart init finished|Welcome to ChCore shell' build/exec_log
```

Expected: timeout ends the intentionally interactive QEMU session with status 124 after the log contains ChCore boot output. No QEMU container remains because Docker uses `--rm`.

- [ ] **Step 6: Review and commit only the documentation**

Run:

```bash
git diff --check -- README.md
git status --short
git add README.md
git diff --cached --check
git commit -m "docs: explain docker shell make workflow"
```

Expected: the commit contains only `README.md`; existing user changes remain unstaged.

- [ ] **Step 7: Record the final verification and repository state**

Run:

```bash
git log -3 --oneline
git status --short
docker ps --filter ancestor="$(./chbuild image)" --format '{{.ID}} {{.Status}}'
```

Expected: the design, Make interface, and documentation commits are visible; the pre-existing working-tree changes are still present; no temporary ChCore container remains running.
