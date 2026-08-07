#!/bin/bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/build" "$tmp_dir/scripts/qemu" "$tmp_dir/bin" \
    "$tmp_dir/run"
cp "$repo_dir/scripts/qemu/qemu_wrapper.sh" "$tmp_dir/scripts/qemu/"

sed \
    -e 's|@qemu@|fake-qemu|g' \
    -e 's|@qemu_options@|-machine raspi3b|g' \
    "$repo_dir/scripts/qemu/emulate.tpl.sh" >"$tmp_dir/build/simulate.sh"
chmod +x "$tmp_dir/build/simulate.sh"

cat >"$tmp_dir/bin/fake-qemu" <<'PY'
#!/usr/bin/env python3
import os
from pathlib import Path
import signal
import socket
import sys
import time

if sys.argv[1:] == ["--version"]:
    print("QEMU emulator version 8.2.0")
    raise SystemExit(0)

mode = os.environ.get("FAKE_QEMU_MODE", "fail")
args_file = os.environ.get("FAKE_QEMU_ARGS")
if args_file:
    Path(args_file).write_text("\n".join(sys.argv[1:]) + "\n")

if mode == "fail":
    print("fake qemu failure reached")
    raise SystemExit(37)
if mode == "success":
    raise SystemExit(0)
if mode != "listen":
    raise SystemExit(f"unknown FAKE_QEMU_MODE: {mode}")

port_arg = next(arg for arg in sys.argv[1:] if arg.startswith("tcp::"))
listener = socket.socket()
listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
listener.bind(("127.0.0.1", int(port_arg.removeprefix("tcp::"))))
listener.listen()
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
while True:
    time.sleep(0.1)
PY
chmod +x "$tmp_dir/bin/fake-qemu"

set +e
(cd "$tmp_dir/run" && PATH="$tmp_dir/bin:$PATH" \
    FAKE_QEMU_MODE=fail "$tmp_dir/build/simulate.sh" >/dev/null 2>&1)
status=$?
set -e

if [ "$status" -ne 37 ]; then
    echo "generated QEMU script returned $status instead of 37" >&2
    exit 1
fi
grep -F 'fake qemu failure reached' "$tmp_dir/build/exec_log" >/dev/null
if [ -e "$tmp_dir/run/exec_log" ]; then
    echo "generated QEMU script wrote exec_log outside build/" >&2
    exit 1
fi

export FAKE_QEMU_ARGS="$tmp_dir/debug-args"
(cd "$tmp_dir/run" && PATH="$tmp_dir/bin:$PATH" FAKE_QEMU_MODE=listen \
    "$tmp_dir/build/simulate.sh" --wait-gdb \
    >"$tmp_dir/debug.out" 2>&1) &
simulate_pid=$!

ready=false
for _ in $(seq 1 100); do
    if grep -q '^\[QEMU\] Waiting for GDB Connection$' \
        "$tmp_dir/debug.out" 2>/dev/null; then
        ready=true
        break
    fi
    if ! kill -0 "$simulate_pid" 2>/dev/null; then
        break
    fi
    sleep 0.05
done
if [ "$ready" != true ]; then
    echo "generated QEMU script did not become ready for GDB" >&2
    pkill -TERM -f "$tmp_dir/bin/fake-qemu" 2>/dev/null || true
    kill "$simulate_pid" 2>/dev/null || true
    wait "$simulate_pid" || true
    exit 1
fi

grep -Fx -- '-S' "$FAKE_QEMU_ARGS" >/dev/null
grep -Fx -- 'tcp::1234' "$FAKE_QEMU_ARGS" >/dev/null
grep -Fx '1234' "$tmp_dir/build/gdb-port" >/dev/null
test -s "$tmp_dir/build/qemu-gdb.pid"
qemu_pid=$(cat "$tmp_dir/build/qemu-gdb.pid")
kill "$qemu_pid"
wait "$simulate_pid"
if [ -e "$tmp_dir/build/qemu-gdb.pid" ]; then
    echo "generated QEMU script left a stale PID file" >&2
    exit 1
fi

export FAKE_QEMU_ARGS="$tmp_dir/normal-args"
(cd "$tmp_dir/run" && PATH="$tmp_dir/bin:$PATH" FAKE_QEMU_MODE=success \
    "$tmp_dir/build/simulate.sh" >/dev/null 2>&1)
if grep -Fx -- '-S' "$FAKE_QEMU_ARGS" >/dev/null; then
    echo "normal QEMU mode unexpectedly paused the CPU" >&2
    exit 1
fi
normal_port=$(cat "$tmp_dir/build/gdb-port")
if [ "$normal_port" -lt 30000 ] || [ "$normal_port" -gt 40000 ]; then
    echo "normal QEMU mode selected invalid port $normal_port" >&2
    exit 1
fi

set +e
(cd "$tmp_dir/run" && PATH="$tmp_dir/bin:$PATH" \
    "$tmp_dir/build/simulate.sh" --bad-option \
    >"$tmp_dir/bad-option.out" 2>&1)
status=$?
set -e
if [ "$status" -ne 2 ]; then
    echo "invalid QEMU option returned $status instead of 2" >&2
    exit 1
fi
grep -F 'Usage:' "$tmp_dir/bad-option.out" >/dev/null

echo "QEMU emulate tests passed"
