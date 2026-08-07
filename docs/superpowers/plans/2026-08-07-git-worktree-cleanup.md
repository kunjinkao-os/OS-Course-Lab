# Git 工作区清理实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 保留现有 `build/`，还原 libc 构建流程生成的源码树状态，并通过仓库级忽略规则防止无价值文件再次污染 Git 工作区。

**Architecture:** 先使用 ChCore libc 自带的 `do_cleanup.sh` 恢复 musl 的备份文件和符号链接覆盖，再单独修改根 `.gitignore`。清理过程不依赖全仓库重置或强制删除；每个阶段都通过限定路径的 Git 状态检查验证边界。

**Tech Stack:** Git、Bash、ChCore libc CMake 辅助脚本、`.gitignore`

## Global Constraints

- 保留 `/Volumes/linux_code/OS-repo/chcore-source/build/`，不执行完整 `make clean`。
- 不使用 `git reset --hard`、`git clean -fd`、`assume-unchanged` 或 `skip-worktree`。
- 不将 musl 已跟踪文件的生成变化加入 `.gitignore`。
- 删除范围只包括仓库中的 `.DS_Store` 和 libc 清理脚本确认管理的生成状态。
- 所有新增 Git 提交使用中文提交信息。

---

## 文件结构

- Modify: `.gitignore` — 仓库级 macOS 元数据和 Python 字节码忽略规则。
- Restore: `user/system-services/chcore-libc/musl-libc/` — 由项目清理脚本恢复到 `HEAD`，不产生持久 diff。
- Delete: `**/.DS_Store` — 删除现有 macOS Finder 元数据，不进入版本控制。

### Task 1: 恢复 musl-libc 的生成状态

**Files:**
- Restore: `user/system-services/chcore-libc/musl-libc/`
- Preserve: `build/`

**Interfaces:**
- Consumes: `do_cleanup.sh TARGET_ABSOLUTE_PATH`，其中参数必须是 musl 目录的绝对路径。
- Produces: 与 `HEAD` 一致的 `musl-libc` 源码树，同时保留现有 `build/`。

- [ ] **Step 1: 确认构建目录和 libc 生成状态存在**

Run:

```bash
test -d /Volumes/linux_code/OS-repo/chcore-source/build
git status --short -- user/system-services/chcore-libc/musl-libc
```

Expected: `test` 返回 0；Git 状态列出 `.bak`、符号链接类型变化和三处补丁修改。

- [ ] **Step 2: 用项目脚本恢复 libc 源码树**

Run:

```bash
bash user/system-services/chcore-libc/libchcore/cmake/do_cleanup.sh \
  /Volumes/linux_code/OS-repo/chcore-source/user/system-services/chcore-libc/musl-libc
```

Expected: 命令返回 0，输出若干 `--- Cleanup ... symlink` 和 `--- Recover ...` 记录。

- [ ] **Step 3: 精确恢复脚本误删的 HEAD 跟踪链接**

`do_cleanup.sh` 会遍历并删除目标树中的所有符号链接。以下 9 个链接原本就在
`HEAD` 中，执行前没有工作区改动，因此只恢复这些已核对路径：

Run:

```bash
git restore -- \
  user/system-services/chcore-libc/musl-libc/arch/sparc \
  user/system-services/chcore-libc/musl-libc/src/thread/riscv64/CMakeLists.txt \
  user/system-services/chcore-libc/musl-libc/src/thread/riscv64/__thread_exit.S \
  user/system-services/chcore-libc/musl-libc/src/thread/riscv64/__unmapself.S \
  user/system-services/chcore-libc/musl-libc/src/thread/sparc \
  user/system-services/chcore-libc/musl-libc/src/thread/x86_64/CMakeLists.txt \
  user/system-services/chcore-libc/musl-libc/src/thread/x86_64/__thread_exit.S \
  user/system-services/chcore-libc/musl-libc/src/thread/x86_64/__unmapself.S \
  user/system-services/chcore-libc/musl-libc/src/thread/x86_64/set_thread_area.c
```

Expected: 命令返回 0，只恢复列出的 9 个 `HEAD` 跟踪链接。

- [ ] **Step 4: 验证 libc 状态干净且构建目录仍在**

Run:

```bash
test -d /Volumes/linux_code/OS-repo/chcore-source/build
test -z "$(git status --short -- user/system-services/chcore-libc/musl-libc)"
find user/system-services/chcore-libc/musl-libc -name '*.bak' -print
```

Expected: 三条命令都返回 0；`find` 无输出，Git 不再报告 `musl-libc` 改动。

### Task 2: 添加垃圾文件忽略规则并提交

**Files:**
- Modify: `.gitignore`
- Delete: `.DS_Store`
- Delete: `docs/.DS_Store`
- Delete: `docs/superpowers/.DS_Store`

**Interfaces:**
- Consumes: Task 1 产生的干净 `musl-libc` 状态。
- Produces: 对 `.DS_Store`、`__pycache__/` 和 `*.py[cod]` 生效的仓库级忽略规则，以及一个中文 Git 提交。

- [ ] **Step 1: 写入最小忽略规则**

Apply this exact patch to `.gitignore`:

```diff
 build/
 .config
+.DS_Store
+__pycache__/
+*.py[cod]
```

- [ ] **Step 2: 验证忽略规则语义**

Run:

```bash
git check-ignore -v --no-index \
  .DS_Store \
  docs/.DS_Store \
  scripts/docker/arm64/__pycache__/probe.pyc \
  scripts/docker/arm64/probe.pyc
```

Expected: 四个路径均被根 `.gitignore` 的新增规则匹配。

- [ ] **Step 3: 删除仓库中现有的 Finder 元数据**

Run:

```bash
find /Volumes/linux_code/OS-repo/chcore-source \
  -path /Volumes/linux_code/OS-repo/chcore-source/.git -prune \
  -o -name .DS_Store -type f -delete
```

Expected: 命令返回 0；随后用同样的 `.git` 排除条件将 `-delete` 改为 `-print`，命令无输出。

- [ ] **Step 4: 检查提交内容**

Run:

```bash
git diff --check
git diff -- .gitignore
git status --short
```

Expected: `git diff --check` 无输出；diff 只显示三条新增忽略规则；状态只显示 `.gitignore`，不再显示 musl 或 `.DS_Store`。

- [ ] **Step 5: 提交忽略规则**

Run:

```bash
git add -- .gitignore
git diff --cached --check
git commit -m '构建：忽略系统和 Python 缓存文件'
```

Expected: 提交成功，提交内容只有 `.gitignore`。

- [ ] **Step 6: 最终验证工作区**

Run:

```bash
git status --short
git log -2 --oneline
test -d /Volumes/linux_code/OS-repo/chcore-source/build
```

Expected: Git 状态无输出；日志顶部是忽略规则提交，其后是最近一次清理计划文档提交；`build/` 仍存在。
