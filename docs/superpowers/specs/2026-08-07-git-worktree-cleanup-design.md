# Git 工作区清理设计

## 背景

当前 Git 工作区中的主要改动位于
`user/system-services/chcore-libc/musl-libc`。这些改动由 ChCore libc 的构建流程生成：

- `do_overrides` 将 musl 原文件保存为 `.bak`，再用 ChCore 覆盖文件的符号链接替换；
- `do_patches` 备份并修改少量 musl 头文件和内部实现；
- 构建流程还会加入 ChCore 专用目录和 AArch64 汇编文件。

这些内容属于可再生的构建状态，并非需要提交的源码修改。工作区中还存在 macOS
生成的 `.DS_Store` 文件。

## 目标

1. 在不删除 `build/` 的前提下恢复干净的 Git 工作区。
2. 使用项目已有的恢复机制，避免手工猜测或覆盖潜在源码修改。
3. 忽略确定无价值的系统和 Python 缓存文件。
4. 保持 libc 移植流程可重复：后续构建仍能重新应用覆盖和补丁。
5. 所有新增 Git 提交使用中文提交信息。

## 非目标

- 不执行完整的 `make clean`，也不删除现有 `build/`。
- 不忽略 musl 中已跟踪文件的变化。
- 不使用 `git update-index --assume-unchanged`、`skip-worktree` 等本地隐藏机制。
- 不直接使用 `git reset --hard` 或 `git clean -fd` 清理整个仓库。

## 方案

### 1. 恢复 libc 移植状态

调用 `user/system-services/chcore-libc/libchcore/cmake/do_cleanup.sh`，将目标指向
`musl-libc`：

- 删除由 override 流程建立的符号链接；
- 将对应 `.bak` 文件恢复为原始文件；
- 删除 patch 流程加入的临时目录和文件；
- 保留仓库外或 Git 已忽略的构建输出。

执行前后都检查 Git 状态。若脚本结束后仍有 musl 改动，则逐项核对，不采用全仓库强制
还原。

### 2. 清理并忽略无价值文件

删除当前发现的 `.DS_Store`，并在仓库根 `.gitignore` 中加入：

```gitignore
.DS_Store
__pycache__/
*.py[cod]
```

规则作用于所有子目录，避免 macOS 元数据和 Python 字节码再次污染状态。

### 3. Git 提交边界

libc 恢复操作应使生成状态回到 `HEAD`，因此不产生需要提交的 musl diff。唯一预期的持久
改动是根 `.gitignore`；该改动单独使用中文提交信息提交，便于审阅和回退。

## 验证

清理完成后执行以下检查：

1. `git status --short` 不再显示 musl 生成状态或 `.DS_Store`；
2. `git diff --check` 无空白错误；
3. 确认 `build/` 仍然存在且未被改动；
4. 确认 `.gitignore` 能匹配 `.DS_Store`、`__pycache__/` 和 Python 字节码；
5. 提交后再次检查状态，确保工作区完全干净。

## 风险与处理

- **恢复脚本遇到异常状态**：立即停止，保留现场并逐项比较 `.bak` 与 `HEAD`。
- **已有真实 musl 修改被混入生成状态**：执行前依赖 `.bak` 与 `HEAD` 的比较结果；执行后
  再检查差异，不用强制重置兜底。
- **后续构建再次弄脏工作区**：这是当前 libc 源码内 porting 机制的预期行为；需要干净
  状态时复用项目清理脚本，而不是扩大忽略规则。
