# VS Code Dev Container 与内核调试迁移设计

## 背景

`OS-Course-Lab` 为学生实验提供了完整的 VS Code 开发体验：Dev Container
内置交叉编译、QEMU、GDB 和 clangd，工作区可通过 F5 自动构建并启动等待
GDB 的 QEMU。当前仓库包含完整 ChCore 源码，目录结构、构建入口和 Docker
工作流均与按 Lab 拆分的实验仓库不同，因此不能直接复制其配置。

本次迁移以实验仓库的使用体验为准，在当前仓库已经验证过的原生 ARM64
Docker 与 `chbuild` 工作流上进行适配。目标用户在 Apple Silicon 主机上用
VS Code 打开仓库并进入 Dev Container 后，可以获得可靠的代码跳转和一键
内核调试体验。

## 目标与范围

本次实现以下能力：

1. Dev Container 提供完整源码构建、QEMU 运行、clangd 和 GDB 调试所需工具。
2. 根目录提供统一的 VS Code 配置，不依赖 `Lab1` 至 `Lab5` 目录。
3. F5 自动准备带调试符号的 Raspi3 内核、启动暂停的 QEMU，并连接 GDB。
4. 调试结束后停止本次 QEMU，避免残留进程和固定端口占用。
5. 普通 `make qemu` 与 `./chbuild run` 行为保持不变。
6. 对容器配置、命令编排、QEMU 等待模式和 VS Code JSON 进行自动验证。

本次仅覆盖 ChCore 内核调试。用户态进程、共享库动态符号加载及内核 GDB
Server 不在本次范围内。现有 `scripts/gdb/gdb.py` 不删除，其用户态辅助能力
留待后续独立设计。

## 方案选择

采用“体验对齐、底层适配”方案：保留
`scripts/docker/arm64/Dockerfile` 及其 recipe-derived 本地镜像，在此基础上补齐
实验环境能力。不会切换到 `ipads/oslab:25.03`，因为该镜像会绕过当前仓库的
ARM64 构建约束、依赖固定方式和镜像缓存策略。

QEMU 调试使用固定端口 `1234`，与实验仓库一致。普通运行继续使用当前生成
脚本选择的随机端口。相比让 VS Code 读取动态端口，固定的专用调试入口更
简单、可预测，并能直接复用 `cppdbg` 的连接模型。

## 容器环境

### Docker 镜像

继续使用 Ubuntu 20.04 ARM64 基础镜像和现有 LLVM 16 软件源。镜像补充：

- `gdb-multiarch`，供 `cppdbg` 通过 GDB/MI 调试 AArch64 ELF；
- `clangd-16`，并提供稳定的 `clangd` 命令名；
- 当前调试和构建链已经依赖的 QEMU、AArch64 binutils、交叉 GCC 与 Python。

新增软件继续放在现有合并的 APT 安装层，保持 `--no-install-recommends` 和
APT 缓存清理。Dockerfile 是 `chbuild` 镜像摘要输入之一，因此工具变化会
自动产生新的本地镜像标签，不会误用旧缓存镜像。

### Dev Container

`.devcontainer/devcontainer.json` 保留原生 `linux/arm64`、`stu` 用户和 UID
同步设置，并新增：

- `--cap-add=SYS_PTRACE`；
- `--security-opt=seccomp=unconfined`；
- bash 作为 Linux 集成终端默认 profile；
- C/C++、Hex Editor、clangd、Makefile、CMake 和 ARM 汇编支持扩展。

QEMU 与 GDB 均在同一个 Dev Container 内运行，所以无需把端口 `1234` 发布
到宿主机。

## 调试命令与 QEMU 生命周期

### 入口

新增以下入口：

- `make qemu-gdb`：面向开发者和 VS Code 的调试入口；
- `./chbuild debug`：准备调试配置、构建并启动等待 GDB 的 QEMU；
- `make qemu-gdb-stop` / `./chbuild debug-stop`：由 VS Code 的
  `postDebugTask` 清理本次调试进程。

`make qemu-gdb` 只委托给 `chbuild`，平台检查、配置修改和运行逻辑集中在
一个地方，避免 Makefile 与 shell 脚本重复实现。

### 调试配置

`./chbuild debug` 按以下规则处理 `.config`：

1. `.config` 不存在时，生成 Raspi3 默认配置；
2. 配置存在但平台不是 Raspi3 时，报错退出并保留原配置；
3. `CHCORE_KERNEL_DEBUG` 为 `OFF` 时只把该值改为 `ON`，保留其他配置；
4. 运行正常的增量构建，让 CMake 根据配置变化重编译需要调试符号的目标；
5. 构建成功后才启动 QEMU。

`.config` 和 `build/` 已被 Git 忽略，因此该过程不会制造待提交文件。若构建
失败，命令返回原始非零状态，VS Code 不会继续连接调试器。

### 生成的模拟器脚本

`scripts/qemu/emulate.tpl.sh` 生成的 `build/simulate.sh` 支持两种明确模式：

- 无参数：保持当前普通运行行为，选择 `30000` 至 `40000` 的随机 GDB
  端口，不暂停 CPU；
- 调试参数：使用端口 `1234`，加入 `-S`，输出
  `[QEMU] Waiting for GDB Connection` 后等待连接。

两种模式都在 `build/gdb-port` 写入实际端口，并把输出记录到
`build/exec_log`。未知参数应输出 usage 并以非零状态退出。

调试模式启动前检查固定端口是否可用。QEMU PID 写入 `build/qemu-gdb.pid`；
正常退出、启动失败和停止任务都清理该文件。停止逻辑读取 Linux
`/proc/<pid>/cmdline`，仅当命令同时包含 `qemu-system-aarch64` 和当前工作区的
`build/kernel.img` 时才发送终止信号；陈旧或不匹配的 PID 不会被盲目终止。

为使 PID 对应真正的 QEMU 进程，QEMU 包装脚本最终以 `exec` 启动模拟器。
该调整不改变现有版本兼容参数转换或退出状态传播。

## VS Code 配置

### `settings.json`

clangd 使用 `${workspaceFolder}/build/kernel/compile_commands.json` 所在目录，
即参数 `--compile-commands-dir=build/kernel`。允许在尚未生成调试信息或源映射
不完整时设置断点，与实验仓库一致。

### `tasks.json`

包含三个职责明确的任务：

1. 普通构建任务，执行 `make`；
2. `Setup QEMU` 后台任务，执行 `make qemu-gdb`，并用等待 GDB 的输出作为
   background problem matcher 的 ready 标记；
3. `Stop QEMU` 任务，执行 `make qemu-gdb-stop`。

所有任务以仓库根目录为工作目录，在 Dev Container 的 bash 中执行。

### `launch.json`

提供 `QEMU (cppdbg)` 配置：

- 调试程序为 `${workspaceFolder}/build/kernel.img`；
- 工作目录为 `${workspaceFolder}`；
- `MIMode` 为 `gdb`；
- `miDebuggerPath` 为 `/usr/bin/gdb-multiarch`；
- 目标架构为 ARM64，远端地址为 `localhost:1234`；
- `preLaunchTask` 为 `Setup QEMU`；
- `postDebugTask` 为 `Stop QEMU`；
- 连接后停在入口，并启用 GDB pretty printing。

用户打开调试侧栏并按 F5 后，不需要手工编辑 `.config`、启动第二个终端或
输入 `target remote`。

## 错误处理

- Docker daemon 不可用、主机不是 ARM64 或镜像构建失败时，沿用 `chbuild`
  现有的明确错误信息。
- 非 Raspi3 配置不会被调试命令覆盖，错误信息给出恢复 Raspi3 配置的命令。
- `1234` 已占用时，在启动 QEMU 前失败并提示结束旧调试会话或释放端口。
- `build/kernel.img` 或 `build/simulate.sh` 缺失时，调试入口先构建；构建失败
  则不产生虚假的 ready 标记。
- PID 文件缺失时停止操作可重复执行并成功返回；PID 陈旧或进程不匹配时只
  清理陈旧记录并给出警告。
- QEMU 的非零退出状态继续传播给调用者，并保留 `build/exec_log` 供排查。

## 文档体验

`README.md` 增加一条从零开始的最短路径：

1. 安装 VS Code 的 Dev Containers 扩展并执行 Reopen in Container；
2. 等待镜像及扩展准备完成；
3. 打开内核源文件、设置断点并按 F5；
4. 使用 Variables、Call Stack、Watch 和 Debug Console；
5. 停止调试，确认 QEMU 随会话清理；
6. 遇到端口、Docker 或非 Raspi3 配置错误时按提示恢复。

文档同时说明普通运行仍使用 `make qemu`，调试入口为 `make qemu-gdb`，避免
用户把暂停等待 GDB 误认为 QEMU 启动失败。

## 验证策略

### 自动测试

- 扩展 `tests/chbuild_arm64_test.sh`：验证 `debug` 帮助文本、Docker 分发、
  Raspi3 限制、只启用内核调试以及失败状态传播。
- 扩展 `tests/make_workflow_test.sh`：验证 `qemu-gdb` 和
  `qemu-gdb-stop` 的精确委托及构建失败行为。
- 扩展 `tests/qemu_emulate_test.sh`：使用 fake QEMU 验证普通随机端口模式、
  `-S` 固定端口模式、ready 标记、日志位置、PID 清理、停止幂等和退出码。
- 新增 VS Code/Dev Container 配置测试：用 Python 标准库解析 JSON，断言
  GDB 路径、程序路径、端口、前后任务、clangd 路径、ptrace 参数和扩展。
- 运行现有全部 shell 与 Python 测试，防止 Docker、Make 和 QEMU 工作流回归。

### 集成验证

1. 构建 recipe-derived ARM64 Docker 镜像；
2. 在镜像中检查 `gdb-multiarch`、`clangd`、`qemu-system-aarch64`、
   `aarch64-linux-gnu-gcc` 和 CMake；
3. 构建带调试信息的 `build/kernel.img`；
4. 启动等待模式 QEMU，用批处理 GDB 加载该 ELF、连接 `localhost:1234`，
   验证目标架构和入口断点；
5. 停止会话，确认端口释放且 PID 文件删除；
6. 运行 `git diff --check` 并复查 Git 状态。

无法通过命令行完全模拟的 VS Code 按钮交互，将通过配置契约测试和真实
QEMU/GDB 连接共同覆盖。

## Git 策略

当前工作区已有大量 musl、`.bak` 与 `.DS_Store` 改动，它们均不属于本次
任务。所有提交使用精确路径暂存，并在提交前检查 `git diff --cached`。

提交按以下边界组织，提交信息使用中文：

1. 设计文档；
2. 容器工具与 Dev Container 体验；
3. QEMU、`chbuild`、Make 与 VS Code 调试工作流及其测试；
4. 用户使用文档。

不修改、删除、格式化或暂存既有的无关工作区内容。
