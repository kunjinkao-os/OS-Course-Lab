#!/bin/bash
# Copyright (c) 2023 Institute of Parallel And Distributed Systems (IPADS), Shanghai Jiao Tong University (SJTU)
# Licensed under the Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#     http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT, MERCHANTABILITY OR FIT FOR A PARTICULAR
# PURPOSE.
# See the Mulan PSL v2 for more details.

set -eo pipefail

basedir=$(cd "$(dirname "$0")" && pwd)
# basedir should be /build directory

case "$#:${1:-}" in
0:)
    port=$(shuf -i 30000-40000 -n 1)
    wait_for_gdb=false
    ;;
1:--wait-gdb)
    port=1234
    wait_for_gdb=true
    ;;
*)
    echo "Usage: $0 [--wait-gdb]" >&2
    exit 2
    ;;
esac

echo "$port" >"$basedir/gdb-port"
qemu_args=(-gdb "tcp::$port")

if [ "$wait_for_gdb" = false ]; then
    "$basedir/../scripts/qemu/qemu_wrapper.sh" \
        @qemu@ "${qemu_args[@]}" @qemu_options@ \
        | tee "$basedir/exec_log"
    exit "${PIPESTATUS[0]}"
fi

if ! python3 - "$port" <<'PY'
import socket
import sys

sock = socket.socket()
try:
    sock.bind(("127.0.0.1", int(sys.argv[1])))
except OSError:
    raise SystemExit(1)
finally:
    sock.close()
PY
then
    echo "GDB port $port is already in use; stop the old debug session first" >&2
    exit 1
fi

pid_file="$basedir/qemu-gdb.pid"
qemu_pid=""
cleanup() {
    if [ -n "$qemu_pid" ] && kill -0 "$qemu_pid" 2>/dev/null; then
        kill "$qemu_pid" 2>/dev/null || true
        wait "$qemu_pid" 2>/dev/null || true
    fi
    rm -f "$pid_file"
}
trap cleanup EXIT INT TERM

"$basedir/../scripts/qemu/qemu_wrapper.sh" \
    @qemu@ -S "${qemu_args[@]}" @qemu_options@ \
    > >(tee "$basedir/exec_log") 2>&1 &
qemu_pid=$!
echo "$qemu_pid" >"$pid_file"

if ! python3 - "$port" "$qemu_pid" <<'PY'
import errno
import os
import socket
import sys
import time

port = int(sys.argv[1])
pid = int(sys.argv[2])
for _ in range(100):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        raise SystemExit(1)

    sock = socket.socket()
    try:
        sock.bind(("127.0.0.1", port))
    except OSError as error:
        if error.errno == errno.EADDRINUSE:
            raise SystemExit(0)
    finally:
        sock.close()
    time.sleep(0.05)
raise SystemExit(1)
PY
then
    echo "QEMU failed to listen on GDB port $port" >&2
    exit 1
fi

echo "[QEMU] Waiting for GDB Connection"
wait "$qemu_pid"
