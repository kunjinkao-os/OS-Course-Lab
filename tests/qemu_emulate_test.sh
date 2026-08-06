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

cat >"$tmp_dir/bin/fake-qemu" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "--version" ]; then
    echo "QEMU emulator version 8.2.0"
    exit 0
fi
echo "fake qemu failure reached"
exit 37
EOF
chmod +x "$tmp_dir/bin/fake-qemu"

set +e
(cd "$tmp_dir/run" && PATH="$tmp_dir/bin:$PATH" \
    "$tmp_dir/build/simulate.sh" >/dev/null 2>&1)
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

echo "QEMU emulate failure test passed"
