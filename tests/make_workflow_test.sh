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
make -s -C "$work_dir" CONFIG=other
assert_log 'defconfig raspi3' 'build'

: >"$MAKE_WORKFLOW_LOG"
make -s -C "$work_dir" CONFIG=other
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
