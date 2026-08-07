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
grep -F 'prepare-image' <<<"$help_output" >/dev/null
grep -F 'linux/arm64' <<<"$help_output" >/dev/null

: >"$DOCKER_LOG"
image_name=$("$repo_dir/chbuild" image)
if [[ ! "$image_name" =~ ^chcore-build:arm64-[0-9a-f]{12}$ ]]; then
    echo "unexpected image name: $image_name" >&2
    exit 1
fi
if [ -s "$DOCKER_LOG" ]; then
    echo "image command unexpectedly contacted Docker" >&2
    exit 1
fi

: >"$DOCKER_LOG"
FAKE_IMAGE_INSPECT_STATUS=0 "$repo_dir/chbuild" prepare-image >/dev/null
grep -E '^info$' "$DOCKER_LOG" >/dev/null
grep -E '^image inspect chcore-build:arm64-[0-9a-f]{12}$' "$DOCKER_LOG" >/dev/null
if grep -E '^(build |run )' "$DOCKER_LOG" >/dev/null; then
    echo "cached prepare-image unexpectedly built or ran a container" >&2
    exit 1
fi

: >"$DOCKER_LOG"
"$repo_dir/chbuild" prepare-image >/dev/null
grep -E '^info$' "$DOCKER_LOG" >/dev/null
grep -E '^image inspect chcore-build:arm64-[0-9a-f]{12}$' "$DOCKER_LOG" >/dev/null
grep -E '^build --platform linux/arm64 -t chcore-build:arm64-[0-9a-f]{12} -f scripts/docker/arm64/Dockerfile \.$' "$DOCKER_LOG" >/dev/null
if grep -E '^run ' "$DOCKER_LOG" >/dev/null; then
    echo "prepare-image unexpectedly ran a command container" >&2
    exit 1
fi

hash_fixture="$tmp_dir/hash-fixture"
mkdir -p "$hash_fixture/scripts/docker/arm64"
cp "$repo_dir/chbuild" "$hash_fixture/chbuild"
cp "$repo_dir/.dockerignore" "$hash_fixture/.dockerignore"
cp "$repo_dir/scripts/docker/arm64/Dockerfile" \
    "$hash_fixture/scripts/docker/arm64/Dockerfile"
cp "$repo_dir/scripts/docker/arm64/read_procmgr_elf_tool.py" \
    "$hash_fixture/scripts/docker/arm64/read_procmgr_elf_tool.py"

for input in \
    .dockerignore \
    scripts/docker/arm64/Dockerfile \
    scripts/docker/arm64/read_procmgr_elf_tool.py; do
    before=$(cd "$hash_fixture" && ./chbuild image)
    printf '\n# tag-input regression marker\n' >>"$hash_fixture/$input"
    after=$(cd "$hash_fixture" && ./chbuild image)
    if [ "$before" = "$after" ]; then
        echo "$input did not affect the recipe-derived image tag" >&2
        exit 1
    fi
    cp "$repo_dir/$input" "$hash_fixture/$input"
done

sha256_path=$(command -v sha256sum || true)
shasum_path=$(command -v shasum || true)
awk_path=$(command -v awk)
if [ -n "$sha256_path" ] && [ -n "$shasum_path" ]; then
    mkdir "$tmp_dir/gnu-hash" "$tmp_dir/macos-hash"
    ln -s "$sha256_path" "$tmp_dir/gnu-hash/sha256sum"
    ln -s "$awk_path" "$tmp_dir/gnu-hash/awk"
    ln -s "$shasum_path" "$tmp_dir/macos-hash/shasum"
    ln -s "$awk_path" "$tmp_dir/macos-hash/awk"
    gnu_name=$(PATH="$tmp_dir/gnu-hash" "$repo_dir/chbuild" image)
    macos_name=$(PATH="$tmp_dir/macos-hash" "$repo_dir/chbuild" image)
    if [ "$gnu_name" != "$macos_name" ]; then
        echo "GNU and macOS hash tools produced different image names" >&2
        exit 1
    fi
fi

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

grep -F \
    'FROM ubuntu:20.04@sha256:722ea796ac2d57eeb3627c58a582fc1acc58be51faf815e1bce1682ae5c092f7' \
    scripts/docker/arm64/Dockerfile >/dev/null
grep -F \
    "8b2a587ffd672c4687e7581dad4b2f6c1bb2ad6b480cd9771ba2ff48e0b8c75d" \
    scripts/docker/arm64/Dockerfile >/dev/null

echo "chbuild ARM64 tests passed"
