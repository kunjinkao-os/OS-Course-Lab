# 在 Apple Silicon 上通过 ARM64 Docker Shell 构建并运行 ChCore

## 适用范围

本指南面向 Apple Silicon（ARM64）Mac 上的首次使用者，推荐先进入仓库提供的 `linux/arm64` 工具链 Docker shell，再使用 `make` 构建 ChCore、使用 `make qemu` 启动 Raspi3。所有命令都应在仓库根目录执行；本指南只承诺 Raspi3 工作流。

`make` 是日常使用入口，底层仍由 `chbuild`、CMake 和生成的 QEMU 启动脚本完成实际工作。本指南后文也保留直接使用 `chbuild` 的方式。

## 前置条件

需要一台 Apple Silicon Mac、已安装的 Docker Desktop、OrbStack 或其他兼容 Docker 的运行中 daemon，以及已克隆的 ChCore 仓库。首次准备工具链镜像需要下载软件包，可能需要一些时间和网络连接。

镜像标签由 Dockerfile、ELF 辅助工具和 `.dockerignore` 推导（recipe-derived）。后续操作会复用该标签和正常的 Docker 层缓存。Ubuntu ARM64 基础镜像按 digest 固定，但 APT 使用的未固定版本软件包不是不可变快照；随着 Ubuntu 或 LLVM 软件源变化，日后重新构建的内容可能不同。

## 1. 检查宿主机与 Docker

先确认宿主机是 ARM64，且 Docker daemon 可以响应：

```bash
uname -m
docker info
```

`uname -m` 应输出 `arm64` 或 `aarch64`。若 Docker 尚未启动，请先启动 Docker Desktop、OrbStack 或所用的兼容 daemon，再继续。

## 2. 准备镜像并进入 Docker shell

先准备与当前仓库 recipe 精确对应的 ARM64 工具链镜像：

```bash
./chbuild prepare-image
chcore_image=$(./chbuild image)
```

`prepare-image` 会在镜像缺失时构建它，已有镜像则直接复用。`image` 只计算并输出精确标签，不会创建镜像，也不会从多个相似的旧标签中任选一个。

可以先确认镜像存在且架构正确：

```bash
docker image inspect "$chcore_image"
docker run --rm --platform linux/arm64 "$chcore_image" uname -m
```

最后一条命令应输出 `aarch64`。然后进入工具链 shell：

```bash
docker run --rm -it \
  --platform linux/arm64 \
  -u "$(id -u):$(id -g)" \
  -v "$PWD:$PWD" \
  -w "$PWD" \
  "$chcore_image" \
  bash
```

该命令把当前仓库挂载到容器中的相同路径，并使用宿主 UID/GID，避免生成归 root 所有的构建文件。退出 shell 时容器会由 `--rm` 自动删除，但仓库中的 `.config`、`build/` 和源码修改都会保留。

后续第 3～5 节的命令在这个 Docker shell 内执行。

## 3. 使用 make 构建

在 Docker shell 的仓库根目录执行：

```bash
make
```

首次构建且 `.config` 不存在时，`make` 会自动生成 Raspi3 默认配置，然后进行完整构建。后续再次执行 `make` 会进行增量构建。

成功构建后会生成 `build/kernel.img` 和 `build/simulate.sh` 等产物。若要在尚无 `build/` 目录时显式生成或重置默认配置，可以运行（已有构建目录时先执行 `make clean`）：

```bash
make defconfig
```

## 4. 使用 make qemu 启动

在 Docker shell 中执行：

```bash
make qemu
```

`make qemu` 每次都会先执行完整的增量构建；只有构建成功后才会启动 QEMU。成功启动时，终端会显示 `[ChCore] uart init finished`、CPU 激活信息，以及 ChCore shell（例如 `Welcome to ChCore shell!`）。

QEMU 以无图形终端模式运行，按 `Ctrl-a x` 退出。日常请使用 `make qemu`，不要直接运行 `build/simulate.sh`。

## 5. 日常增量构建与清理

修改代码后通常直接执行：

```bash
make
make qemu
```

需要从头重新构建但保留当前 `.config` 时使用：

```bash
make clean
```

需要删除构建目录与 `.config` 时使用：

```bash
make distclean
```

怀疑旧构建状态造成问题时，使用 `make distclean`，之后再次执行 `make` 即可重新生成 Raspi3 默认配置并构建。

查看 Make 入口：

```bash
make help
```

完成工作后使用 `exit` 离开 Docker shell。

## 6. 在宿主机直接使用 make 或 chbuild

在 Apple Silicon 宿主机的仓库根目录直接执行以下命令也可以工作：

```bash
make
make qemu
```

此时 Makefile 仍会调用 `chbuild`，由它自动准备并启动临时 ARM64 容器；在 Docker shell 内执行时，`chbuild` 会检测当前容器，不会嵌套启动另一个 Docker 容器。

需要使用底层入口时，Make 命令大致对应：

```bash
./chbuild defconfig raspi3  # .config 不存在时
./chbuild build
./chbuild run
```

清理和查询命令对应：

```bash
./chbuild clean
./chbuild distclean
./chbuild --help
```

`./chbuild run` 与 `make qemu` 最终都会调用生成的 `build/simulate.sh`，后者仍是 QEMU 参数、串口日志和 GDB 端口选择的唯一来源。

## 7. 构建产物与日志

- `build/kernel.img`：供 Raspi3 QEMU 加载的内核镜像。
- `build/simulate.sh`：由配置/构建流程生成的 QEMU 启动脚本；日常请通过 `make qemu` 调用它。
- `build/exec_log`：QEMU 串口输出的日志，便于回看启动信息和故障。
- `build/gdb-port`：每次启动时写入的 QEMU GDB 调试端口。

## 8. 常见问题

- Docker daemon 未启动：运行 `docker info` 检查；若连接失败，启动 Docker Desktop、OrbStack 或其他兼容 daemon 后重试。
- 宿主不是 ARM64：该工作流要求 `uname -m` 输出 `arm64` 或 `aarch64`。请在受支持的 ARM64 环境中运行。
- 当前 recipe 镜像不存在：运行 `./chbuild prepare-image`。不要把 `./chbuild image` 当成创建镜像的命令。
- 缺少 `.config`：直接运行 `make`，它会自动生成 Raspi3 默认配置；使用底层入口时运行 `./chbuild defconfig raspi3`。
- 缺少 `build/simulate.sh`：先执行 `make`；之后通过 `make qemu` 启动，而不是直接执行该脚本。
- 旧构建状态：运行 `make distclean` 删除构建目录与 `.config`，然后重新执行 `make`。
- 需要强制重建当前 recipe 镜像：先解析精确标签，只删除该标签，再重新准备。不要按通配符删除其他镜像。

  ```bash
  chcore_image=$(./chbuild image)
  docker image rm "$chcore_image"
  ./chbuild prepare-image
  ```

- QEMU 终端似乎无响应：确认当前焦点在运行 QEMU 的终端，等待启动日志；退出请按 `Ctrl-a x`。若启动脚本不存在，先重新构建。

## 命令速查

在宿主机准备镜像并进入 Docker shell：

```bash
uname -m
docker info

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

在 Docker shell 中构建并启动：

```bash
make
make qemu
```

日常清理、重新配置或查询帮助：

```bash
make clean
make distclean
make help
```
