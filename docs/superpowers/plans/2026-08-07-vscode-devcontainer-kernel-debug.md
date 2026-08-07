# VS Code Dev Container 与内核调试迁移实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `OS-Course-Lab` 的 Dev Container、clangd 与 F5 内核调试体验适配到完整 ChCore 源码仓库。

**Architecture:** 保留当前原生 ARM64 recipe-derived Docker 镜像，在镜像和 Dev Container 中补齐编辑器调试能力。由 `chbuild` 统一准备调试配置和控制 QEMU 生命周期，生成的 `simulate.sh` 区分普通随机端口运行与固定 `1234` 端口等待 GDB 两种模式；根目录 `.vscode` 只负责编排这些稳定命令。

**Tech Stack:** Bash、GNU Make、Docker/Dev Containers、QEMU AArch64、GDB/MI、VS Code cppdbg、clangd、Python 3 标准库。

## Global Constraints

- 仅支持 Apple Silicon/ARM64 主机和 `linux/arm64` Dev Container。
- VS Code 调试仅覆盖 Raspi3 的 ChCore 内核，不实现用户态进程或动态库调试。
- F5 使用固定 GDB 端口 `1234`；普通 `make qemu` 保持随机端口且不暂停。
- F5 可自动把 `CHCORE_KERNEL_DEBUG` 改为 `ON`，但不得覆盖其他 `.config` 设置，也不得自动切换非 Raspi3 平台。
- 调试结束必须停止本次 QEMU 并清理 `build/qemu-gdb.pid`。
- 保留现有 `scripts/gdb/gdb.py` 和普通 Docker/Make/QEMU 行为。
- 只精确暂存本计划文件；不得暂存或修改现有 musl、`.bak`、`.DS_Store` 改动。
- 所有实现提交信息使用中文。

---

## File Map

- `scripts/docker/arm64/Dockerfile`：安装容器内 GDB 和 clangd 命令。
- `.devcontainer/devcontainer.json`：定义 ptrace 权限、终端设置和 VS Code 扩展。
- `tests/devcontainer_config_test.py`：静态验证 Dockerfile 与 Dev Container 契约。
- `scripts/qemu/qemu_wrapper.sh`：保留版本兼容转换并用 `exec` 启动真实 QEMU。
- `scripts/qemu/emulate.tpl.sh`：生成普通模式和等待 GDB 模式，记录端口、日志和 PID。
- `tests/qemu_emulate_test.sh`：用 fake QEMU 验证两种模式、ready 标记和 PID 清理。
- `chbuild`：实现 `debug`、`debug-stop`、配置保护和进程身份验证。
- `Makefile`：向开发者暴露 `qemu-gdb` 与 `qemu-gdb-stop`。
- `tests/chbuild_arm64_test.sh`：验证新命令的 Docker 分发和帮助契约。
- `tests/chbuild_debug_test.sh`：在临时 fixture 中验证配置修改、平台保护和停止逻辑。
- `tests/make_workflow_test.sh`：验证 Make 目标精确委托给 `chbuild`。
- `.vscode/settings.json`：指定 clangd compile database 并允许任意位置断点。
- `.vscode/tasks.json`：定义构建、启动 QEMU 和停止 QEMU 任务。
- `.vscode/launch.json`：定义 `QEMU (cppdbg)` GDB/MI 会话。
- `tests/vscode_debug_config_test.py`：解析并断言三份 VS Code JSON 的连接契约。
- `README.md`：记录 Reopen in Container、F5、普通运行和排障流程。

---

### Task 1: 补齐 Dev Container 调试工具与权限

**Files:**
- Create: `tests/devcontainer_config_test.py`
- Modify: `scripts/docker/arm64/Dockerfile`
- Modify: `.devcontainer/devcontainer.json`

**Interfaces:**
- Consumes: 现有 `linux/arm64` Docker recipe、用户 `stu` 和 VS Code Dev Containers JSON 格式。
- Produces: `/usr/bin/gdb-multiarch`、`/usr/local/bin/clangd`、ptrace 能力，以及后续 `launch.json` 可依赖的扩展环境。

- [ ] **Step 1: 写失败的容器配置契约测试**

创建 `tests/devcontainer_config_test.py`：

```python
#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
dockerfile = (ROOT / "scripts/docker/arm64/Dockerfile").read_text()
devcontainer = json.loads((ROOT / ".devcontainer/devcontainer.json").read_text())

for package in ("gdb-multiarch", "clangd-16"):
    assert package in dockerfile, f"Dockerfile missing {package}"
assert "ln -s /usr/bin/clangd-16 /usr/local/bin/clangd" in dockerfile

run_args = devcontainer["runArgs"]
assert "--cap-add=SYS_PTRACE" in run_args
assert "--security-opt=seccomp=unconfined" in run_args

vscode = devcontainer["customizations"]["vscode"]
expected_extensions = {
    "ms-vscode.cpptools",
    "ms-vscode.hexeditor",
    "llvm-vs-code-extensions.vscode-clangd",
    "ms-vscode.makefile-tools",
    "twxs.cmake",
    "dan-c-underwood.arm",
}
assert expected_extensions <= set(vscode["extensions"])
assert vscode["settings"]["terminal.integrated.defaultProfile.linux"] == "bash"

print("Dev Container configuration tests passed")
```

- [ ] **Step 2: 运行测试并确认它因缺少工具和权限失败**

Run: `python3 tests/devcontainer_config_test.py`

Expected: FAIL，第一项错误为 `Dockerfile missing gdb-multiarch`。

- [ ] **Step 3: 在 ARM64 Dockerfile 中加入 GDB 与 clangd**

在现有 APT 包列表中加入：

```dockerfile
        clangd-16 \
        gdb-multiarch \
```

把现有工具链接步骤扩展为：

```dockerfile
RUN chmod 0755 /usr/local/bin/read_procmgr_elf_tool \
    && ln -s /usr/bin/clangd-16 /usr/local/bin/clangd \
    && ln -s /usr/bin/clang-tidy-16 /usr/local/bin/clang-tidy \
    && ln -s /usr/bin/make /usr/local/bin/gmake \
    && groupadd --gid "${USER_GID}" "${USERNAME}" \
    && useradd --uid "${USER_UID}" --gid "${USER_GID}" \
        --create-home --shell /bin/bash "${USERNAME}" \
    && usermod -aG sudo "${USERNAME}" \
    && passwd -d "${USERNAME}"
```

- [ ] **Step 4: 更新 Dev Container 配置**

将 `.devcontainer/devcontainer.json` 更新为合法 JSON：

```json
{
  "name": "ChCore-Dev",
  "build": {
    "dockerfile": "../scripts/docker/arm64/Dockerfile",
    "context": "..",
    "options": ["--platform=linux/arm64"]
  },
  "remoteUser": "stu",
  "updateRemoteUserUID": true,
  "runArgs": [
    "--hostname", "Chcore",
    "--platform", "linux/arm64",
    "--cap-add=SYS_PTRACE",
    "--security-opt=seccomp=unconfined"
  ],
  "customizations": {
    "vscode": {
      "extensions": [
        "ms-vscode.cpptools",
        "ms-vscode.hexeditor",
        "llvm-vs-code-extensions.vscode-clangd",
        "ms-vscode.makefile-tools",
        "twxs.cmake",
        "dan-c-underwood.arm"
      ],
      "settings": {
        "terminal.integrated.defaultProfile.linux": "bash"
      }
    }
  }
}
```

- [ ] **Step 5: 运行契约测试与格式检查**

Run: `python3 tests/devcontainer_config_test.py && git diff --check`

Expected: 输出 `Dev Container configuration tests passed`，`git diff --check` 无输出。

- [ ] **Step 6: 精确暂存并提交**

```bash
git add -- scripts/docker/arm64/Dockerfile .devcontainer/devcontainer.json tests/devcontainer_config_test.py
git diff --cached --check
git diff --cached --name-status
git commit -m '开发环境：补齐容器内核调试工具'
```

Expected staged paths: 仅上述三个文件。

---

### Task 2: 为生成的 QEMU 脚本加入可靠的等待 GDB 模式

**Files:**
- Modify: `scripts/qemu/qemu_wrapper.sh`
- Modify: `scripts/qemu/emulate.tpl.sh`
- Modify: `tests/qemu_emulate_test.sh`

**Interfaces:**
- Consumes: CMake 替换的 `@qemu@`、`@qemu_options@`，以及 Python 3 的 `/proc/net/tcp` 监听检查。
- Produces: `build/simulate.sh`；无参数为普通模式，`--wait-gdb` 为端口 `1234` 的暂停模式；写入 `build/gdb-port`、`build/exec_log`、调试时的 `build/qemu-gdb.pid`。

- [ ] **Step 1: 扩展 QEMU 回归测试，先表达两种模式的契约**

在 `tests/qemu_emulate_test.sh` 中保留现有非零退出码用例，并用以下程序增加可监听 GDB 端口的 fake QEMU：

```bash
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
Path(os.environ["FAKE_QEMU_ARGS"]).write_text("\n".join(sys.argv[1:]) + "\n")
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
```

测试以后台方式执行 `build/simulate.sh --wait-gdb`，等待 ready 标记，然后断言：

```bash
grep -Fx -- '-S' "$FAKE_QEMU_ARGS"
grep -Fx -- 'tcp::1234' "$FAKE_QEMU_ARGS"
grep -Fx '1234' "$tmp_dir/build/gdb-port"
test -s "$tmp_dir/build/qemu-gdb.pid"
grep -F '[QEMU] Waiting for GDB Connection' "$tmp_dir/debug.out"
```

随后终止 PID 文件中的进程、等待模拟脚本退出，并断言 `qemu-gdb.pid` 已删除。再运行无参数模式，断言参数中没有 `-S`，端口位于 `30000..40000`。最后传入 `--bad-option`，断言退出码为 `2` 且输出 usage。

- [ ] **Step 2: 运行测试并确认等待模式尚未实现**

Run: `bash tests/qemu_emulate_test.sh`

Expected: FAIL，`simulate.sh` 不识别 `--wait-gdb` 或未传入 `-S`。

- [ ] **Step 3: 让 QEMU wrapper 保留参数边界并 exec 模拟器**

在 `scripts/qemu/qemu_wrapper.sh` 中把 `qemu_options` 改成数组；保留 `verlte`、`verlt` 与版本提取逻辑；旧版 AArch64 QEMU 分支遍历数组，把值为 `raspi3b` 的元素替换为 `raspi3`。最终使用：

```bash
exec "$qemu" "${qemu_options[@]}"
```

删除旧的字符串参数重组、`sed` 替换和裸 `$qemu $qemu_options`。

- [ ] **Step 4: 在模板中实现普通和等待 GDB 两种模式**

在 `scripts/qemu/emulate.tpl.sh` 中实现：

```bash
basedir=$(cd "$(dirname "$0")" && pwd)
case "$#:${1:-}" in
0:) port=$(shuf -i 30000-40000 -n 1); wait_for_gdb=false ;;
1:--wait-gdb) port=1234; wait_for_gdb=true ;;
*) echo "Usage: $0 [--wait-gdb]" >&2; exit 2 ;;
esac
echo "$port" >"$basedir/gdb-port"
qemu_args=(-gdb "tcp::$port")
```

普通模式以前台 pipeline 运行 wrapper 与 `tee "$basedir/exec_log"`，并返回 `${PIPESTATUS[0]}`。调试模式先用 Python socket `bind(("127.0.0.1", 1234))` 检查端口；随后后台运行：

```bash
"$basedir/../scripts/qemu/qemu_wrapper.sh" \
    @qemu@ -S "${qemu_args[@]}" @qemu_options@ \
    > >(tee "$basedir/exec_log") 2>&1 &
qemu_pid=$!
echo "$qemu_pid" >"$basedir/qemu-gdb.pid"
```

通过 `trap 'rm -f "$pid_file"' EXIT INT TERM` 清理 PID 文件，并使用以下 Python 检查在最多 5 秒内进入监听状态：

```bash
if ! python3 - "$port" "$qemu_pid" <<'PY'
from pathlib import Path
import sys
import time

port_suffix = f":{int(sys.argv[1]):04X}"
pid = int(sys.argv[2])
for _ in range(100):
    if not Path(f"/proc/{pid}").exists():
        raise SystemExit(1)
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            rows = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        if any(row.split()[1].endswith(port_suffix)
               and row.split()[3] == "0A" for row in rows):
            raise SystemExit(0)
    time.sleep(0.05)
raise SystemExit(1)
PY
then
    kill "$qemu_pid" 2>/dev/null || true
    wait "$qemu_pid" 2>/dev/null || true
    echo "QEMU failed to listen on GDB port $port" >&2
    exit 1
fi
echo "[QEMU] Waiting for GDB Connection"
wait "$qemu_pid"
```

- [ ] **Step 5: 运行 QEMU 脚本测试**

Run: `bash tests/qemu_emulate_test.sh`

Expected: 输出 `QEMU emulate tests passed`，覆盖普通失败传播、固定端口等待、PID 清理和错误参数。

- [ ] **Step 6: 提交 QEMU 生命周期改动**

```bash
git add -- scripts/qemu/qemu_wrapper.sh scripts/qemu/emulate.tpl.sh tests/qemu_emulate_test.sh
git diff --cached --check
git diff --cached --name-status
git commit -m '调试：增加 QEMU 等待 GDB 模式'
```

---

### Task 3: 在 chbuild 与 Make 中实现调试命令

**Files:**
- Modify: `chbuild`
- Modify: `Makefile`
- Modify: `tests/chbuild_arm64_test.sh`
- Create: `tests/chbuild_debug_test.sh`
- Modify: `tests/make_workflow_test.sh`

**Interfaces:**
- Consumes: `build/simulate.sh --wait-gdb`、`.config` 的 CMake cache 格式、`build/qemu-gdb.pid`。
- Produces: `./chbuild debug`、`./chbuild debug-stop`、`make qemu-gdb`、`make qemu-gdb-stop`。

- [ ] **Step 1: 先扩展 Make 和 chbuild 命令契约测试**

在 `tests/make_workflow_test.sh` 增加：

```bash
reset_fixture
make -s -C "$work_dir" qemu-gdb
assert_log 'debug'

: >"$MAKE_WORKFLOW_LOG"
make -s -C "$work_dir" qemu-gdb-stop
assert_log 'debug-stop'
```

在 `tests/chbuild_arm64_test.sh` 中断言帮助包含 `debug`、`debug-stop`，并用现有 fake Docker 验证宿主机执行 `./chbuild debug` 时产生的容器命令以 `chbuild debug` 结尾。

- [ ] **Step 2: 创建 chbuild 本地行为测试**

创建 `tests/chbuild_debug_test.sh`。在 `mktemp -d` fixture 中复制 `chbuild` 和默认配置，以 fake `cmake` 创建 `build/simulate.sh` 并记录参数。覆盖：

```bash
# 无配置：生成 Raspi3，启用 debug，构建并等待 GDB。
(cd "$fixture" && PATH="$fake_bin:$PATH" ./chbuild --local debug)
grep -Fx 'CHCORE_PLAT:STRING=raspi3' "$fixture/.config"
grep -Fx 'CHCORE_KERNEL_DEBUG:BOOL=ON' "$fixture/.config"
grep -Fx -- '--wait-gdb' "$fixture/simulate.log"

# 已有 Raspi3 配置：只把 OFF 改成 ON，保留其他键。
grep -Fx 'CHCORE_USER_DEBUG:BOOL=OFF' "$fixture/.config"

# 非 Raspi3：失败且文件逐字节不变。
cp "$fixture/.config" "$fixture/config.before"
if (cd "$fixture" && PATH="$fake_bin:$PATH" ./chbuild --local debug); then exit 1; fi
cmp "$fixture/config.before" "$fixture/.config"
```

停止测试启动一个路径名为 `qemu-system-aarch64` 的 sleep fixture，其命令行带当前 fixture 的绝对 `build/kernel.img`，写入 PID 后执行 `debug-stop` 并断言进程退出。另测缺失 PID 文件幂等成功，以及不匹配的 sleep PID 不被结束。

- [ ] **Step 3: 运行命令测试并确认失败**

Run: `bash tests/make_workflow_test.sh && bash tests/chbuild_arm64_test.sh && bash tests/chbuild_debug_test.sh`

Expected: 前两个测试在缺少新目标/帮助时失败，新测试在 `invalid command 'debug'` 处失败。

- [ ] **Step 4: 在 chbuild 中实现配置准备与 debug 启动**

加入：

```bash
debug_pid_file="$cmake_build_dir/qemu-gdb.pid"

_prepare_debug_config() {
    if [ ! -f "$config_file" ]; then
        defconfig raspi3
    fi
    if ! grep -q '^CHCORE_PLAT:STRING=raspi3$' "$config_file"; then
        _echo_err "Kernel debugging supports only raspi3; run '$self distclean' before switching platforms"
        return 1
    fi
    if grep -q '^CHCORE_KERNEL_DEBUG:BOOL=OFF$' "$config_file"; then
        sed -i 's/^CHCORE_KERNEL_DEBUG:BOOL=OFF$/CHCORE_KERNEL_DEBUG:BOOL=ON/' "$config_file"
        _echo_info "Enabled CHCORE_KERNEL_DEBUG in $config_file"
    elif ! grep -q '^CHCORE_KERNEL_DEBUG:BOOL=ON$' "$config_file"; then
        _echo_err "Missing CHCORE_KERNEL_DEBUG in $config_file; run '$self config' to repair it"
        return 1
    fi
}

debug() {
    _prepare_debug_config
    build
    exec "$cmake_build_dir/simulate.sh" --wait-gdb
}
```

- [ ] **Step 5: 实现经过进程身份验证的停止命令**

加入：

```bash
debug_stop() {
    if [ ! -f "$debug_pid_file" ]; then
        _echo_info "No QEMU debug session is running"
        return 0
    fi

    local pid cmdline build_dir kernel_path
    read -r pid <"$debug_pid_file"
    build_dir=$(cd "$cmake_build_dir" && pwd)
    kernel_path="$build_dir/kernel.img"
    if [[ ! "$pid" =~ ^[0-9]+$ ]] || [ ! -r "/proc/$pid/cmdline" ]; then
        rm -f "$debug_pid_file"
        _echo_warn "Removed stale QEMU debug PID file"
        return 0
    fi

    cmdline=$(tr '\0' ' ' <"/proc/$pid/cmdline")
    if [[ "$cmdline" != *qemu-system-aarch64* || "$cmdline" != *"$kernel_path"* ]]; then
        rm -f "$debug_pid_file"
        _echo_warn "Refused to stop PID $pid because it is not this ChCore QEMU"
        return 0
    fi

    kill "$pid"
    rm -f "$debug_pid_file"
    _echo_succ "Stopped QEMU debug session"
}
```

帮助文本同时列出 `debug` 和 `debug-stop`。

在 `_main` 的通用函数分发前加入：

```bash
        debug-stop)
            if [ -f /.dockerenv ] || [[ $run_in_docker == false ]]; then
                debug_stop
            else
                _docker_run "$@"
            fi
            exit
            ;;
```

这使宿主机首次调用进入容器后不再递归分发，并让连字符保持为稳定 CLI。

- [ ] **Step 6: 增加 Make 目标和帮助文本**

```make
.PHONY: all defconfig build qemu qemu-gdb qemu-gdb-stop clean distclean help

qemu-gdb:
	$(CHBUILD) debug

qemu-gdb-stop:
	$(CHBUILD) debug-stop
```

帮助新增：

```make
		'make qemu-gdb      build a debug kernel, then wait for VS Code/GDB' \
		'make qemu-gdb-stop stop the active QEMU debug session' \
```

- [ ] **Step 7: 运行 chbuild 和 Make 测试**

```bash
bash tests/chbuild_arm64_test.sh
bash tests/chbuild_debug_test.sh
bash tests/make_workflow_test.sh
```

Expected: 分别输出 `chbuild ARM64 tests passed`、`chbuild debug tests passed`、`Make workflow tests passed`。

- [ ] **Step 8: 提交命令工作流**

```bash
git add -- chbuild Makefile tests/chbuild_arm64_test.sh tests/chbuild_debug_test.sh tests/make_workflow_test.sh
git diff --cached --check
git diff --cached --name-status
git commit -m '调试：加入一键内核调试命令'
```

---

### Task 4: 添加根目录 VS Code 调试配置

**Files:**
- Create: `.vscode/settings.json`
- Create: `.vscode/tasks.json`
- Create: `.vscode/launch.json`
- Create: `tests/vscode_debug_config_test.py`

**Interfaces:**
- Consumes: `make qemu-gdb`、`make qemu-gdb-stop`、`build/kernel.img`、`/usr/bin/gdb-multiarch`、端口 `1234`。
- Produces: `QEMU (cppdbg)` F5 配置、clangd compile database 定位和自动前后任务。

- [ ] **Step 1: 写失败的 VS Code 配置契约测试**

创建 `tests/vscode_debug_config_test.py`：

```python
#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
load = lambda name: json.loads((ROOT / ".vscode" / name).read_text())
settings = load("settings.json")
tasks = load("tasks.json")["tasks"]
launches = load("launch.json")["configurations"]

assert settings["clangd.arguments"] == ["--compile-commands-dir=build/kernel"]
assert settings["debug.allowBreakpointsEverywhere"] is True
tasks_by_label = {task["label"]: task for task in tasks}
assert tasks_by_label["Build ChCore"]["command"] == "make"
assert tasks_by_label["Setup QEMU"]["command"] == "make qemu-gdb"
assert tasks_by_label["Setup QEMU"]["isBackground"] is True
background = tasks_by_label["Setup QEMU"]["problemMatcher"]["background"]
assert background["endsPattern"] == r"^\[QEMU\] Waiting for GDB Connection$"
assert tasks_by_label["Stop QEMU"]["command"] == "make qemu-gdb-stop"

assert len(launches) == 1
launch = launches[0]
assert launch["name"] == "QEMU (cppdbg)"
assert launch["program"] == "${workspaceFolder}/build/kernel.img"
assert launch["cwd"] == "${workspaceFolder}"
assert launch["MIMode"] == "gdb"
assert launch["miDebuggerPath"] == "/usr/bin/gdb-multiarch"
assert launch["targetArchitecture"] == "arm64"
assert launch["miDebuggerServerAddress"] == "localhost:1234"
assert launch["preLaunchTask"] == "Setup QEMU"
assert launch["postDebugTask"] == "Stop QEMU"
assert launch["stopAtEntry"] is True
print("VS Code debug configuration tests passed")
```

- [ ] **Step 2: 运行测试并确认配置文件不存在**

Run: `python3 tests/vscode_debug_config_test.py`

Expected: FAIL with `FileNotFoundError` for `.vscode/settings.json`。

- [ ] **Step 3: 创建三份 VS Code JSON**

`.vscode/settings.json` 使用：

```json
{
  "clangd.arguments": ["--compile-commands-dir=build/kernel"],
  "debug.allowBreakpointsEverywhere": true
}
```

`.vscode/tasks.json` 定义 `Build ChCore`（`make`）、`Setup QEMU`（`make qemu-gdb`，后台任务，ready pattern 为 `^\\[QEMU\\] Waiting for GDB Connection$`）和 `Stop QEMU`（`make qemu-gdb-stop`）。三个任务的 `options.cwd` 都为 `${workspaceFolder}`。

`.vscode/launch.json` 创建唯一配置：

```json
{
  "version": "0.2.0",
  "configurations": [{
    "name": "QEMU (cppdbg)",
    "type": "cppdbg",
    "request": "launch",
    "program": "${workspaceFolder}/build/kernel.img",
    "args": [],
    "cwd": "${workspaceFolder}",
    "environment": [],
    "externalConsole": false,
    "stopAtEntry": true,
    "stopAtConnect": true,
    "setupCommands": [{
      "description": "Enable pretty-printing for gdb",
      "text": "-enable-pretty-printing",
      "ignoreFailures": true
    }],
    "MIMode": "gdb",
    "targetArchitecture": "arm64",
    "miDebuggerServerAddress": "localhost:1234",
    "miDebuggerPath": "/usr/bin/gdb-multiarch",
    "preLaunchTask": "Setup QEMU",
    "postDebugTask": "Stop QEMU"
  }]
}
```

- [ ] **Step 4: 运行 JSON 契约测试**

Run: `python3 tests/vscode_debug_config_test.py`

Expected: 输出 `VS Code debug configuration tests passed`。

- [ ] **Step 5: 提交 VS Code 配置**

```bash
git add -- .vscode/settings.json .vscode/tasks.json .vscode/launch.json tests/vscode_debug_config_test.py
git diff --cached --check
git diff --cached --name-status
git commit -m '开发环境：添加 VS Code 一键内核调试'
```

---

### Task 5: 补充使用文档并执行端到端验证

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: 前四个任务产出的容器、命令和 VS Code 配置。
- Produces: 从 Reopen in Container 到停止 F5 会话的用户操作说明，以及经过真实工具链验证的最终迁移。

- [ ] **Step 1: 在 README 写入最短开发路径**

在 Docker shell 章节后新增：

```markdown
### VS Code Dev Container and kernel debugging

1. Install the VS Code **Dev Containers** extension.
2. Open this repository and run **Dev Containers: Reopen in Container**.
3. Wait for the ARM64 image and workspace extensions to finish installing.
4. Open a kernel source file, set a breakpoint, select **QEMU (cppdbg)**,
   and press F5.
5. Stop the debugger normally. The post-debug task stops QEMU and releases
   GDB port 1234.

F5 creates a Raspi3 configuration when needed and enables
`CHCORE_KERNEL_DEBUG` without changing other options. It refuses to overwrite
a non-Raspi3 configuration. Use `make qemu` for normal execution,
`make qemu-gdb` to start a manual debug session, and `make qemu-gdb-stop` to
clean up a stale session.
```

在 Troubleshooting 中加入以下三项：

```markdown
- If GDB port 1234 is busy, stop the previous debug session or run
  `make qemu-gdb-stop`, then press F5 again.
- Kernel debugging supports only Raspi3. Preserve any configuration you need,
  run `make distclean`, and let F5 create the Raspi3 debug configuration.
- If `gdb-multiarch` or `clangd` is missing, run **Dev Containers: Rebuild
  Container** so VS Code uses the current recipe-derived image.
```

- [ ] **Step 2: 运行所有快速测试**

```bash
bash tests/chbuild_arm64_test.sh
bash tests/chbuild_debug_test.sh
bash tests/make_workflow_test.sh
bash tests/qemu_emulate_test.sh
python3 tests/read_procmgr_elf_tool_test.py
python3 tests/devcontainer_config_test.py
python3 tests/vscode_debug_config_test.py
git diff --check
```

Expected: 每项测试输出各自的 `passed` 消息，`git diff --check` 无输出。

- [ ] **Step 3: 构建并检查新的 recipe-derived Docker 镜像**

```bash
./chbuild prepare-image
debug_image=$(./chbuild image)
docker run --rm --platform linux/arm64 "$debug_image" bash -lc \
  'test "$(uname -m)" = aarch64 && gdb-multiarch --version && clangd --version && qemu-system-aarch64 --version && aarch64-linux-gnu-gcc --version && cmake --version'
```

Expected: 容器架构为 `aarch64`，五个工具均存在并以状态 `0` 退出。

- [ ] **Step 4: 构建调试内核并确认 DWARF 信息**

在 Dev Container 终端运行：

```bash
make qemu-gdb >build/debug-smoke.log 2>&1 &
debug_launcher_pid=$!
for attempt in $(seq 1 100); do
  grep -q '^\[QEMU\] Waiting for GDB Connection$' build/debug-smoke.log && break
  kill -0 "$debug_launcher_pid"
  sleep 0.1
done
aarch64-linux-gnu-readelf --debug-dump=info build/kernel.img >/dev/null
```

Expected: ready 标记出现，`readelf` 状态为 `0` 且 ELF 含 DWARF 信息。

- [ ] **Step 5: 做真实 GDB 连接冒烟测试**

继续在同一个 Dev Container 内运行：

```bash
gdb-multiarch -q -batch build/kernel.img \
  -ex 'set architecture aarch64' \
  -ex 'target remote localhost:1234' \
  -ex 'info registers pc' \
  -ex 'break start' \
  -ex 'continue' \
  -ex 'info source'
make qemu-gdb-stop
test ! -e build/qemu-gdb.pid
```

Expected: GDB 成功连接 AArch64 target，断点命中内核入口并显示源码；停止后 PID 文件不存在。入口验证前先运行 `aarch64-linux-gnu-nm build/kernel.img | rg ' start$'`；若镜像使用不同入口符号，则使用该命令定位到的全局入口符号，不得跳过源码断点验证。

- [ ] **Step 6: 提交用户文档**

```bash
git add -- README.md
git diff --cached --check
git diff --cached --name-status
git commit -m '文档：补充 VS Code 内核调试指南'
```

- [ ] **Step 7: 最终 Git 审计**

```bash
git log -6 --oneline
git status --short
git diff --check
```

Expected: 本次新增实现形成中文提交；原有 musl、`.bak`、`.DS_Store` 状态仍在但未进入本次提交；不存在本次任务的未提交文件或空白错误。
