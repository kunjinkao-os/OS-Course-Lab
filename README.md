# ChCore 微内核完整源码

本仓库包含 ChCore 微内核、用户态系统服务、运行库、构建脚本和测试的完整源码，适合进行源码阅读、功能开发、系统构建和内核调试。它不是只保留练习接口的学生实验裁剪版。

当前开发环境以 Raspi3 平台和 `linux/arm64` 工具链为主，并提供以下入口：

- 基于 Docker 的一致构建环境；
- VS Code Dev Container 开发环境；
- `make` 驱动的日常构建与 QEMU 启动流程；
- VS Code F5 一键启动 QEMU 并连接 GDB 的内核调试流程。
- 注意，必须make后才能启动语言服务器clangd

## 仓库结构

```text
.
├── kernel/        ChCore 内核源码
├── user/          用户态库、系统服务和应用
├── scripts/       构建、Docker、QEMU 和 GDB 辅助脚本
├── tests/         构建流程与工具脚本测试
├── docs/          开发环境和使用文档
├── .devcontainer/ VS Code Dev Container 配置
├── .vscode/       VS Code 构建、调试与代码分析配置
├── chbuild        ChCore 构建入口
└── Makefile       推荐的日常命令入口
```

## 推荐开发环境

当前 Docker 工作流面向 ARM64 主机，推荐使用：

- Apple Silicon Mac；
- Docker Desktop、OrbStack 或其他正在运行的 Docker 兼容服务；
- VS Code；
- VS Code 的 **Dev Containers** 扩展。

`chbuild` 会在首次使用时构建本地 `linux/arm64` 工具链镜像，后续复用由 Dockerfile 和相关构建文件计算出的镜像标签及 Docker 缓存。Ubuntu ARM64 基础镜像按 digest 固定，但 APT 软件包没有固定到不可变快照，因此不同时间重新构建的镜像内容仍可能略有差异。

VS Code Dev Container 默认直接拉取已验证的 ARM64 镜像 `docker.io/kunjinkao512/chcore-dev:2026-08-07-arm64`，无需在首次打开工作区时重新安装系统工具链。工作区扩展仍由 `.devcontainer/devcontainer.json` 自动安装。

## 快速开始

### 使用 VS Code Dev Container

这是推荐的开发方式：

1. 使用 VS Code 打开仓库根目录。
2. 安装 **Dev Containers** 扩展。
3. 执行 **Dev Containers: Reopen in Container**。
4. 等待 ARM64 工具链镜像拉取和工作区扩展安装完成。
5. 在容器终端执行：

```sh
make
make qemu
```

默认情况下，仓库在容器内位于 `/workspaces/chcore-source`。推荐始终在该容器路径中完成配置、构建、运行和调试。

`make` 会在缺少 `.config` 时自动生成 Raspi3 默认配置，然后构建完整系统。`make qemu` 会先进行增量构建，再使用 QEMU 启动 ChCore。

libc 构建会在 `build/user/chcore-libc/musl-libc/` 中复制 musl 源码、应用移植补丁并生成编译产物。该目录由 `.gitignore` 忽略，仓库中跟踪的 musl 源码保持原样。克隆后无需设置本地 Git 忽略标记；开发时修改 `user/system-services/chcore-libc/musl-libc/` 或 `libchcore/porting/` 中的文件，随后重新执行 CMake 配置，使修改进入构建目录。

QEMU 使用无图形串口模式运行。按 `Ctrl-a x` 可以退出。

### 直接从宿主机运行

在 Apple Silicon 宿主机上，也可以直接执行：

```sh
make
make qemu
```

此时 `chbuild` 会自动准备并启动临时 ARM64 容器，不要求宿主机安装交叉编译工具链。

这是 Dev Container 之外的备选入口。CMake 缓存包含源码绝对路径，因此不要在宿主机路径和 `/workspaces/chcore-source` 之间直接复用同一个 `build/`；切换开发方式前应删除可再生的 `build/` 并重新构建。

底层 `chbuild` 入口与上述流程等价：

```sh
./chbuild defconfig raspi3
./chbuild build
./chbuild run
```

### 进入交互式 Docker Shell

如果需要长期使用容器内终端，可以先准备当前配方对应的镜像：

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

进入容器后，在仓库根目录继续使用 `make`、`make qemu` 等命令即可。

## 常用命令

| 命令 | 作用 |
| --- | --- |
| `make` | 缺少配置时生成 Raspi3 默认配置，然后增量构建 ChCore |
| `make defconfig` | 显式生成默认平台配置，默认平台为 Raspi3 |
| `make qemu` | 构建并在 QEMU 中启动 ChCore |
| `make qemu-gdb` | 构建调试内核，并让 QEMU 在端口 1234 等待 GDB |
| `make qemu-gdb-stop` | 停止当前工作区的 QEMU 调试会话 |
| `make clean` | 删除构建产物，保留 `.config` |
| `make distclean` | 删除构建产物和 `.config` |
| `make help` | 显示 Make 工作流帮助 |
| `./chbuild --help` | 显示底层构建命令和参数 |

构建成功后，主要产物位于 `build/`：

- `build/kernel.img`：带调试信息的内核 ELF；
- `build/simulate.sh`：由构建系统生成的 QEMU 启动脚本；
- `build/qemu.log`：QEMU 输出日志；
- `build/gdb-port`：当前 QEMU GDB 端口；
- `build/qemu-gdb.pid`：调试模式下的 QEMU 进程记录。

日常启动请使用 `make qemu` 或 `./chbuild run`，不要直接依赖生成的 `build/simulate.sh`。

## VS Code 内核调试

Dev Container 内已经配置 `clangd`、`gdb-multiarch`、QEMU 和 AArch64 交叉工具链。

1. 在 VS Code 中通过 Dev Container 打开仓库。
2. 打开内核源码并设置断点。
3. 在“运行和调试”中选择 **QEMU (cppdbg)**。
4. 按 F5。

VS Code 会依次执行以下操作：

1. 调用 `make qemu-gdb` 准备 Raspi3 调试配置并构建内核；
2. 启动 QEMU，使其暂停并在 `localhost:1234` 等待连接；
3. 使用 `/usr/bin/gdb-multiarch` 加载 `build/kernel.img`；
4. 调试结束后调用 `make qemu-gdb-stop` 清理 QEMU 进程和端口。

调试入口会在必要时创建 Raspi3 配置，并启用 `CHCORE_KERNEL_DEBUG`，但不会覆盖已有的其他配置项。如果当前 `.config` 不是 Raspi3 配置，调试命令会拒绝继续；请先保存需要的配置，再执行 `make distclean` 后重试。

VS Code Debug Console 使用 GDB/MI。执行普通 GDB 命令时需要添加 `-exec` 前缀，例如：

```text
-exec info registers
-exec bt
-exec monitor system_reset
```

如果只想手动启动等待 GDB 的 QEMU，可执行：

```sh
make qemu-gdb
```

调试完成或端口被占用时执行：

```sh
make qemu-gdb-stop
```

## 配置与代码分析

- 默认平台由 Make 变量 `PLATFORM` 控制，当前默认值为 `raspi3`；例如可用 `make defconfig PLATFORM=raspi3` 显式指定。
- `clangd` 从 `build/kernel/compile_commands.json` 获取内核编译参数，因此首次代码分析前应至少成功构建一次。
- 头文件建议使用 `#pragma once`，不使用传统的 `#ifndef` include guard。
- 公共内核头文件放在 `kernel/include/`；架构相关头文件放在 `kernel/include/arch/<架构>/arch/`。

## Git 工作区说明

`build/`、`.config`、`.DS_Store` 和 Python 字节码缓存均已忽略。ChCore libc 的构建流程会在 `user/system-services/chcore-libc/musl-libc/` 中临时应用补丁和符号链接覆盖，因此构建期间该目录可能出现在 `git status` 中。

不要提交这些自动生成的 libc 移植状态。清理或提交前应查看：

```sh
git status --short
git diff -- user/system-services/chcore-libc/musl-libc
```

处理工作区时不要使用不加路径限制的 `git clean` 或强制重置，以免删除本地源码改动。

## 常见问题

### 无法连接 Docker

先执行：

```sh
docker info
```

如果连接失败，请启动 Docker Desktop、OrbStack 或其他 Docker 兼容服务后重试。

### GDB 端口 1234 被占用

先停止上一次调试会话：

```sh
make qemu-gdb-stop
```

然后重新按 F5 或执行 `make qemu-gdb`。

### Dev Container 中缺少 clangd 或 gdb-multiarch

先拉取已发布镜像，再执行 **Dev Containers: Rebuild Container**：

```sh
docker pull kunjinkao512/chcore-dev:2026-08-07-arm64
```

### CMake 报告源码目录与缓存目录不一致

这表示 `build/CMakeCache.txt` 记录的源码绝对路径与当前工作区路径不同，通常发生在同一个 `build/` 先后从宿主机路径和 Dev Container 的 `/workspaces/...` 路径使用时。

当前 Dev Container 固定使用 `/workspaces/<仓库名>`，本仓库通常为 `/workspaces/chcore-source`。如果希望完全在容器中开发，请不要再从宿主机执行构建命令。

仓库已经关闭 VS Code CMake Tools 的自动配置，并将其手动配置目录隔离到 `build/cmake-tools`。构建 ChCore 时请使用 `make`，不要执行 **CMake: Configure**，以免绕过 `chbuild` 的配置流程。

首次从宿主机构建切换到 Dev Container 时，在容器终端只删除可再生的构建目录并重新构建；`.config` 会保留：

```sh
rm -rf -- build
make
```

### 缺少 build/simulate.sh

先运行 `make` 完成构建，再使用 `make qemu` 启动。不要手工创建或直接维护 `build/simulate.sh`。

### 检查镜像架构

```sh
docker run --rm --platform linux/arm64 \
  kunjinkao512/chcore-dev:2026-08-07-arm64 uname -m
```

预期输出为 `aarch64`。

## 内核与系统调用调试开关

- `kernel/include/common/debug.h` 定义了内核调试相关选项。
- `user/chcore-libc/src/chcore-port/syscall_dispatcher.c` 中的 `TRACE_SYSCALL` 控制 libc 系统调用跟踪，默认关闭。
- 为避免日志量过大或递归输出，`SYS_sched_yield`、`SYS_writev`、`SYS_ioctl`、`SYS_read` 和 `SYS_io_submit` 等调用不会全部打印。

## 更多文档

- [Apple Silicon ARM64 Docker 与 QEMU 使用指南](docs/arm64-docker-qemu-guide.md)
- [VS Code Dev Container 与内核调试迁移设计](docs/superpowers/specs/2026-08-07-vscode-devcontainer-kernel-debug-design.md)

## 许可证

本项目使用木兰宽松许可证第 2 版（Mulan PSL v2），详见 [LICENSE](LICENSE)。
