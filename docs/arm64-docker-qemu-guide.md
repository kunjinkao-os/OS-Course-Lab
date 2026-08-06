# 在 Apple Silicon 上使用 ARM64 Docker 构建并运行 ChCore

## 适用范围

本指南面向 Apple Silicon（ARM64）Mac 上的首次使用者，介绍如何通过 Docker 的 `linux/arm64` 工具链镜像构建 ChCore，并使用 QEMU 启动 Raspi3 配置。所有命令都应在仓库根目录执行；本指南只承诺 Raspi3 工作流。

## 前置条件

需要一台 Apple Silicon Mac、已安装的 Docker Desktop、OrbStack 或其他兼容 Docker 的运行中 daemon，以及已克隆的 ChCore 仓库。首次配置会构建工具链镜像并下载软件包，可能需要一些时间和网络连接。

镜像标签由 Dockerfile、ELF 辅助工具和 `.dockerignore` 推导（recipe-derived）。后续操作会复用该标签和正常的 Docker 层缓存。Ubuntu ARM64 基础镜像按 digest 固定，但 APT 使用的未固定版本软件包不是不可变快照；随着 Ubuntu 或 LLVM 软件源变化，日后重新构建的内容可能不同。

## 1. 检查宿主机与 Docker

先确认宿主机是 ARM64，且 Docker daemon 可以响应：

```bash
uname -m
docker info
```

`uname -m` 应输出 `arm64` 或 `aarch64`。若 Docker 尚未启动，请先启动 Docker Desktop、OrbStack 或所用的兼容 daemon，再继续。

## 2. 配置 Raspi3 并检查 ARM64 镜像

首次使用时，请先配置 Raspi3：

```bash
./chbuild defconfig raspi3
```

这一步会创建 `.config` 和构建目录；在 Docker 环境中，它也会在首次需要时构建本地 `linux/arm64` 工具链镜像并下载软件包。

不要把 `./chbuild image` 当作创建镜像的命令：它只计算当前 recipe-derived 镜像名称，并不创建镜像。因此必须先执行上面的 `defconfig raspi3`，然后再检查镜像及其架构：

```bash
chcore_image=$(./chbuild image)
docker image inspect "$chcore_image"
docker run --rm --platform linux/arm64 "$chcore_image" uname -m
```

最后一条命令应输出 `aarch64`。如果 `docker image inspect` 找不到镜像，确认前面的 `defconfig raspi3` 已成功完成。

## 3. 完整构建

配置完成后构建全部目标：

```bash
./chbuild build
```

该命令需要 `.config`；若提示缺少它，请回到第 2 节执行 `./chbuild defconfig raspi3`。构建成功后会生成内核镜像和 QEMU 启动脚本。

## 4. 使用 QEMU 启动

使用统一入口启动 Raspi3 QEMU：

```bash
./chbuild run
```

成功启动时，终端会显示 `[ChCore] uart init finished`、CPU 激活信息，以及 ChCore shell（例如 `Welcome to ChCore shell!`）。QEMU 以无图形终端模式运行；按 `Ctrl-a x` 退出。

请使用 `./chbuild run`，不要直接把 `build/simulate.sh` 当作日常启动入口。

## 5. 日常增量构建与清理

修改代码后通常直接再次运行 `./chbuild build`，Docker 镜像和构建缓存会被复用。需要从头重新构建但保留当前 `.config` 时使用：

```bash
./chbuild clean
```

需要删除构建目录与 `.config` 时使用：

```bash
./chbuild distclean
```

切换平台或怀疑旧构建状态造成问题时，使用 `distclean`，之后重新执行 `./chbuild defconfig raspi3`。

查看所有公共命令及参数：

```bash
./chbuild --help
```

## 6. 构建产物与日志

- `build/kernel.img`：供 Raspi3 QEMU 加载的内核镜像。
- `build/simulate.sh`：构建生成的 QEMU 启动脚本；日常请通过 `./chbuild run` 调用它。
- `build/exec_log`：QEMU 串口输出的日志，便于回看启动信息和故障。
- `build/gdb-port`：每次启动时写入的 QEMU GDB 调试端口。

## 7. 常见问题

- Docker daemon 未启动：运行 `docker info` 检查；若连接失败，启动 Docker Desktop、OrbStack 或其他兼容 daemon 后重试。
- 宿主不是 ARM64：该工作流要求 `uname -m` 输出 `arm64` 或 `aarch64`。请在受支持的 ARM64 环境中运行。
- 缺少 `.config`：先运行 `./chbuild defconfig raspi3`，再运行构建或启动命令。
- 缺少 `build/simulate.sh`：先执行 `./chbuild build`；之后通过 `./chbuild run` 启动，而不是直接执行该脚本。
- 旧构建状态：运行 `./chbuild distclean` 删除构建目录与 `.config`，然后重新执行 `./chbuild defconfig raspi3` 和 `./chbuild build`。
- 需要强制重建 recipe 镜像：先精确解析当前标签，只删除该标签，再重新配置；不要按通配符删除其他镜像。

  ```bash
  chcore_image=$(./chbuild image)
  docker image rm "$chcore_image"
  ./chbuild defconfig raspi3
  ```

- QEMU 终端似乎无响应：确认当前焦点在运行 QEMU 的终端，等待启动日志；退出请按 `Ctrl-a x`。若启动脚本不存在，先重新构建。

## 命令速查

首次使用按以下顺序执行：

```bash
uname -m
docker info

./chbuild defconfig raspi3

chcore_image=$(./chbuild image)
docker image inspect "$chcore_image"
docker run --rm --platform linux/arm64 "$chcore_image" uname -m

./chbuild build
./chbuild run
```

日常清理、重新配置或查询帮助：

```bash
./chbuild clean
./chbuild distclean
./chbuild --help
```
