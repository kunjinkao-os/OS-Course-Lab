# ARM64 Docker 与 QEMU 使用指南设计

## 目标

为在 Apple Silicon macOS 上首次使用 ChCore 的开发者提供一份独立、可直接照做的中文指南。读者无需理解 Dockerfile 或 `chbuild` 内部实现，也能完成 ARM64 容器构建、Raspi3 配置、完整编译和 QEMU `-nographic` 启动。

## 文档位置与入口

- 新建 `docs/arm64-docker-qemu-guide.md` 作为完整指南。
- 在根目录 `README.md` 的 Apple Silicon 使用说明中增加该指南的相对链接。
- README 保留现有快速命令，不复制完整排障内容。

## 内容结构

指南按实际操作顺序组织：

1. 适用范围与前置条件：Apple Silicon、Docker Desktop/OrbStack、仓库目录。
2. 环境检查：确认宿主架构、Docker daemon、精确 recipe 镜像名称与容器 `aarch64`。
3. 首次构建：依次运行 `defconfig raspi3` 和 `build`，解释首次镜像构建耗时及缓存行为。
4. QEMU 启动：运行 `./chbuild run`，说明 `-nographic`、可识别的启动输出与 `Ctrl-a x` 退出方式。
5. 日常工作流：增量构建、`clean`、`distclean` 的使用边界。
6. 产物与日志：说明 `build/kernel.img`、`build/simulate.sh`、`build/exec_log` 和 `build/gdb-port`。
7. 常见问题：Docker 未启动、非 ARM64 宿主、未配置、缺少模拟脚本、旧构建状态、镜像重建、QEMU 退出。
8. 命令速查：汇总最常用且可复制的命令。

## 准确性边界

- 只描述已经实现并通过动态验收的 `raspi3` 流程，不暗示 Raspi4 可由 `./chbuild run` 启动。
- 明确镜像标签由仓库内构建配方派生，不宣称 APT 软件包快照完全可复现。
- 不要求用户直接运行 `build/simulate.sh`；统一推荐 `./chbuild run`。
- 所有命令以仓库根目录为当前目录。
- 故障排查先给诊断命令，再给恢复操作，避免建议破坏性 Git 命令。

## 验证

- 对文档中的 shell 命令与当前 `chbuild --help`、README 和实现逐项核对。
- 检查 Markdown 链接和路径存在。
- 运行 `git diff --check`，确保没有格式问题。
- 最终确认指南包含完整三命令流程、`aarch64` 检查、`Ctrl-a x` 和日志路径。
