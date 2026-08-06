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
grep -F 'linux/arm64' <<<"$help_output" >/dev/null

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

cat >"$tmp_dir/sha256sum" <<'EOF'
#!/bin/bash
if [ "$#" -gt 0 ]; then
    exit 7
fi
printf '%s  -\n' '0000000000000000000000000000000000000000000000000000000000000000'
EOF
chmod +x "$tmp_dir/sha256sum"

: >"$DOCKER_LOG"
if "$repo_dir/chbuild" build >"$tmp_dir/out" 2>&1; then
    echo "hash command failure unexpectedly accepted" >&2
    exit 1
fi
grep -F 'Cannot hash Docker image inputs' "$tmp_dir/out" >/dev/null
if grep -E '^(image inspect|build |run )' "$DOCKER_LOG" >/dev/null; then
    echo "docker execution continued after hash command failure" >&2
    exit 1
fi

echo "chbuild ARM64 tests passed"
