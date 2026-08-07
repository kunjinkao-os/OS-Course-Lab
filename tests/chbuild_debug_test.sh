#!/bin/bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

fixture="$tmp_dir/fixture"
fake_bin="$tmp_dir/bin"
mkdir -p "$fixture/scripts/build/defconfigs" \
    "$fixture/scripts/build/cmake" "$fake_bin"
cp "$repo_dir/chbuild" "$fixture/chbuild"

cat >"$fixture/scripts/build/defconfigs/raspi3.config" <<'EOF'
CHCORE_CROSS_COMPILE:STRING=aarch64-linux-gnu-
CHCORE_PLAT:STRING=raspi3
CHCORE_KERNEL_DEBUG:BOOL=OFF
CHCORE_USER_DEBUG:BOOL=OFF
EOF

cat >"$fake_bin/cmake" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"$CHBUILD_DEBUG_CMAKE_LOG"
mkdir -p build
if [ "${1:-}" = "--build" ]; then
    cat >build/simulate.sh <<'SIMULATE'
#!/bin/bash
printf '%s\n' "$*" >simulate.log
exit "${FAKE_SIMULATE_STATUS:-0}"
SIMULATE
    chmod +x build/simulate.sh
    exit "${FAKE_CMAKE_BUILD_STATUS:-0}"
fi
EOF
chmod +x "$fake_bin/cmake"

export CHBUILD_DEBUG_CMAKE_LOG="$tmp_dir/cmake.log"

reset_fixture() {
    rm -rf "$fixture/build" "$fixture/.config" "$fixture/simulate.log"
    : >"$CHBUILD_DEBUG_CMAKE_LOG"
}

reset_fixture
(cd "$fixture" && PATH="$fake_bin:$PATH" ./chbuild --local debug)
grep -Fx 'CHCORE_PLAT:STRING=raspi3' "$fixture/.config" >/dev/null
grep -Fx 'CHCORE_KERNEL_DEBUG:BOOL=ON' "$fixture/.config" >/dev/null
grep -Fx 'CHCORE_USER_DEBUG:BOOL=OFF' "$fixture/.config" >/dev/null
grep -Fx -- '--wait-gdb' "$fixture/simulate.log" >/dev/null

reset_fixture
cat >"$fixture/.config" <<'EOF'
CHCORE_PLAT:STRING=raspi3
CHCORE_KERNEL_DEBUG:BOOL=OFF
CHCORE_USER_DEBUG:BOOL=OFF
PRESERVE_ME:STRING=yes
EOF
(cd "$fixture" && PATH="$fake_bin:$PATH" ./chbuild --local debug)
grep -Fx 'CHCORE_KERNEL_DEBUG:BOOL=ON' "$fixture/.config" >/dev/null
grep -Fx 'CHCORE_USER_DEBUG:BOOL=OFF' "$fixture/.config" >/dev/null
grep -Fx 'PRESERVE_ME:STRING=yes' "$fixture/.config" >/dev/null

rm -f "$fixture/simulate.log"
if (cd "$fixture" && PATH="$fake_bin:$PATH" FAKE_CMAKE_BUILD_STATUS=23 \
    ./chbuild --local debug >"$tmp_dir/build-failure.out" 2>&1); then
    echo "debug unexpectedly ignored a build failure" >&2
    exit 1
fi
test ! -e "$fixture/simulate.log"

reset_fixture
cat >"$fixture/.config" <<'EOF'
CHCORE_PLAT:STRING=raspi4
CHCORE_KERNEL_DEBUG:BOOL=OFF
PRESERVE_ME:STRING=yes
EOF
cp "$fixture/.config" "$tmp_dir/config.before"
if (cd "$fixture" && PATH="$fake_bin:$PATH" \
    ./chbuild --local debug >"$tmp_dir/raspi4.out" 2>&1); then
    echo "debug unexpectedly accepted a non-Raspi3 configuration" >&2
    exit 1
fi
cmp "$tmp_dir/config.before" "$fixture/.config"
grep -F 'supports only raspi3' "$tmp_dir/raspi4.out" >/dev/null

mkdir -p "$fixture/build" "$tmp_dir/proc"
: >"$fixture/build/kernel.img"

sleep 30 &
qemu_pid=$!
mkdir -p "$tmp_dir/proc/$qemu_pid"
printf 'qemu-system-aarch64\0-kernel\0%s\0' \
    "$fixture/build/kernel.img" >"$tmp_dir/proc/$qemu_pid/cmdline"
printf '%s\n' "$qemu_pid" >"$fixture/build/qemu-gdb.pid"
(cd "$fixture" && CHBUILD_PROC_ROOT="$tmp_dir/proc" \
    ./chbuild --local debug-stop)
wait "$qemu_pid" 2>/dev/null || true
if kill -0 "$qemu_pid" 2>/dev/null; then
    echo "debug-stop did not stop the matching QEMU process" >&2
    kill "$qemu_pid"
    exit 1
fi
test ! -e "$fixture/build/qemu-gdb.pid"

sleep 30 &
other_pid=$!
mkdir -p "$tmp_dir/proc/$other_pid"
printf 'sleep\0' >"$tmp_dir/proc/$other_pid/cmdline"
printf '%s\n' "$other_pid" >"$fixture/build/qemu-gdb.pid"
(cd "$fixture" && CHBUILD_PROC_ROOT="$tmp_dir/proc" \
    ./chbuild --local debug-stop)
if ! kill -0 "$other_pid" 2>/dev/null; then
    echo "debug-stop killed an unrelated process" >&2
    exit 1
fi
kill "$other_pid"
wait "$other_pid" 2>/dev/null || true
test ! -e "$fixture/build/qemu-gdb.pid"

(cd "$fixture" && CHBUILD_PROC_ROOT="$tmp_dir/proc" \
    ./chbuild --local debug-stop)

echo "chbuild debug tests passed"
