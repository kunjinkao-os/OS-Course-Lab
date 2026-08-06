# ARM64 Docker 与 QEMU 使用指南实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 编写一份可直接照做的中文指南，帮助 Apple Silicon macOS 用户在原生 ARM64 Docker 中构建 ChCore，并通过 QEMU `-nographic` 启动 Raspi3 产物。

**Architecture:** 完整操作说明放在独立的 `docs/arm64-docker-qemu-guide.md`，根目录 README 只增加入口并保留现有快速流程。指南严格复用当前已经验收的 `chbuild` 接口，不引入新的脚本或构建行为。

**Tech Stack:** Markdown、Bash 命令、Docker/OrbStack/Docker Desktop、ChCore `chbuild`、QEMU system AArch64。

## Global Constraints

- 所有命令默认从 ChCore 仓库根目录执行。
- 宿主环境限定为 Apple Silicon macOS，Docker 容器必须报告 `aarch64`。
- 构建和运行平台限定为 `raspi3`；不得暗示 `./chbuild run` 支持 Raspi4。
- QEMU 通过 `./chbuild run` 启动，使用生成的 `build/simulate.sh` 与 `-nographic -serial mon:stdio`。
- 使用 `Ctrl-a x` 退出 QEMU。
- 镜像名称使用 `./chbuild image` 精确解析；不得用通配符选择任意旧标签。
- 镜像标签描述为 recipe-derived local cache tag；不得宣称未锁版本的 APT 软件包完全可复现。
- 排障步骤不得使用 `git reset --hard`、`git checkout --` 或 `git clean -fdx`。

---

### Task 1: 编写中文指南并添加 README 入口

**Files:**
- Create: `docs/arm64-docker-qemu-guide.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: `./chbuild image|defconfig raspi3|build|run|clean|distclean|--help`，以及构建产物 `build/kernel.img`、`build/simulate.sh`、`build/exec_log`、`build/gdb-port`。
- Produces: 面向用户的中文操作指南，以及 README 中指向该指南的相对链接。

- [ ] **Step 1: 创建指南正文**

创建 `docs/arm64-docker-qemu-guide.md`，使用以下一级标题和顺序：

```markdown
# 在 Apple Silicon 上使用 ARM64 Docker 构建并运行 ChCore

## 适用范围
## 前置条件
## 1. 检查宿主机与 Docker
## 2. 配置 Raspi3 并检查 ARM64 镜像
## 3. 完整构建
## 4. 使用 QEMU 启动
## 5. 日常增量构建与清理
## 6. 构建产物与日志
## 7. 常见问题
## 命令速查
```

正文必须包含以下可复制命令：

```bash
uname -m
docker info

./chbuild defconfig raspi3

chcore_image=$(./chbuild image)
docker image inspect "$chcore_image"
docker run --rm --platform linux/arm64 "$chcore_image" uname -m

./chbuild build
./chbuild run

./chbuild clean
./chbuild distclean
./chbuild --help
```

明确说明首次使用时 `./chbuild image` 只计算名称，并不创建镜像；因此先运行 `./chbuild defconfig raspi3`，再执行 `docker image inspect` 和容器 `uname -m` 检查。解释首次配置会构建镜像并下载软件包，后续会使用 recipe-derived 标签和 Docker 层缓存；APT 软件包不是不可变快照。说明成功启动时可看到 `[ChCore] uart init finished`、CPU 激活信息和 ChCore shell，按 `Ctrl-a x` 退出。说明 `clean` 用于重新构建而保留 `.config`，`distclean` 删除构建目录与 `.config`，切换平台或怀疑旧状态时使用后者。列出四个产物路径及用途。

常见问题必须覆盖：Docker daemon 未启动、宿主不是 ARM64、缺少 `.config`、缺少 `build/simulate.sh`、旧构建状态、需要强制重建 recipe 镜像、QEMU 终端似乎无响应。强制重建镜像时先精确解析标签，再只删除该标签：

```bash
chcore_image=$(./chbuild image)
docker image rm "$chcore_image"
./chbuild defconfig raspi3
```

- [ ] **Step 2: 在 README 增加指南入口**

在 README 的 Apple Silicon 前置条件段落后、`## Build and run` 前增加：

```markdown
完整中文教程请参阅 [ARM64 Docker 与 QEMU 使用指南](docs/arm64-docker-qemu-guide.md)。
```

- [ ] **Step 3: 核对命令与实现**

运行：

```bash
./chbuild --help
rg -n 'image\)|defconfig\)|build\)|run\)|clean\)|distclean\)' chbuild
test -f scripts/docker/arm64/Dockerfile
test -f scripts/qemu/emulate.tpl.sh
```

预期：`--help` 列出指南使用的全部公共命令，`chbuild` 存在对应 dispatch 分支，两个实现文件存在。

- [ ] **Step 4: 验证指南覆盖范围和链接**

运行：

```bash
rg -n 'aarch64|defconfig raspi3|chbuild build|chbuild run|Ctrl-a x|kernel\.img|simulate\.sh|exec_log|gdb-port|distclean|recipe-derived' docs/arm64-docker-qemu-guide.md
rg -n 'docs/arm64-docker-qemu-guide\.md' README.md
test -f docs/arm64-docker-qemu-guide.md
git diff --check
```

预期：每个要求的术语、命令、产物和 README 链接都存在，目标文件存在，`git diff --check` 退出 0。

- [ ] **Step 5: 人工自审**

逐段确认：命令都从仓库根目录执行；首次镜像检查位于 `defconfig raspi3` 之后；只承诺 Raspi3；没有直接推荐运行 `build/simulate.sh`；没有完全可复现镜像承诺；故障恢复不包含破坏性 Git 命令；中文说明对首次使用者无需阅读实现即可理解。

- [ ] **Step 6: 提交文档**

```bash
git add README.md docs/arm64-docker-qemu-guide.md
git commit -m "docs: add arm64 docker qemu usage guide"
```

预期：提交仅包含 README 入口和独立中文指南。
