# LAB TODO Comment Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the student-lab TODO boundaries and their directly associated instructional comments to the matching complete implementations in `chcore-source`, without changing executable source text.

**Architecture:** Treat each Lab1–Lab5 snapshot as an annotation source and map its TODO regions to the corresponding complete-source file by function and statement anchors. Insert only comments with `apply_patch`; verify each lab batch immediately, then run repository-wide marker coverage and source-preservation checks.

**Tech Stack:** C, AArch64 assembly, POSIX shell, ripgrep, Git, `apply_patch`

## Global Constraints

- Source repository: `/Volumes/linux_code/OS-repo/OS-Course-Lab`.
- Target repository: `/Volumes/linux_code/OS-repo/chcore-source`.
- Source scope is code under `Lab1` through `Lab5`; `Pages` and Lab6 ordinary TODO comments are excluded.
- Include every canonical `LAB* TODO BEGIN/END` boundary, including `LAB7 TODO` boundaries stored in Lab5, plus directly associated explanations, hints, and step comments.
- Use semantic anchors rather than source line numbers.
- Add comments only. Do not modify, delete, move, or reformat executable source.
- Preserve source comment wording; adjust leading indentation only when required by the target context.
- The current student tree contains 72 `BEGIN` and 73 `END` lines because `Lab3/kernel/object/thread.c` retained one filled-code marker in the wrong position. Use its original scaffold commit (`e41b376d`) to restore the canonical four paired regions in that function while retaining directly related explanatory comments from the current tree.

---

### Task 1: Establish the Annotation Inventory and Baseline

**Files:**
- Read: `/Volumes/linux_code/OS-repo/OS-Course-Lab/Lab1/**`
- Read: `/Volumes/linux_code/OS-repo/OS-Course-Lab/Lab2/**`
- Read: `/Volumes/linux_code/OS-repo/OS-Course-Lab/Lab3/**`
- Read: `/Volumes/linux_code/OS-repo/OS-Course-Lab/Lab4/**`
- Read: `/Volumes/linux_code/OS-repo/OS-Course-Lab/Lab5/**`
- Read: all 27 matching target files listed in Tasks 2–6

**Interfaces:**
- Consumes: source files containing the regex `(?i)\bLAB\s*[0-9]+\s+TODO\b`
- Produces: a 27-file source-to-target map and a pre-edit target snapshot at Git commit `c21922a`

- [ ] **Step 1: Confirm the target worktree starts at the approved design commit**

Run:

```bash
git status --short
git rev-parse --short HEAD
```

Expected: `c21922a`; the only status entry is the untracked implementation plan itself.

- [ ] **Step 2: Enumerate the annotation source files**

Run:

```bash
rg -l -P '(?i)\bLAB\s*[0-9]+\s+TODO\b' \
  /Volumes/linux_code/OS-repo/OS-Course-Lab/Lab{1,2,3,4,5} \
  --glob '*.{c,h,S,ld,cpp,cc,inc}' | sort -V
```

Expected: exactly 27 files: 3 in Lab1, 7 in Lab2, 5 in Lab3, 6 in Lab4, and 6 in Lab5.

- [ ] **Step 3: Record the source anomaly used for canonical mapping**

Run:

```bash
git -C /Volumes/linux_code/OS-repo/OS-Course-Lab \
  show e41b376d:Lab3/kernel/object/thread.c | sed -n '220,275p'
```

Expected: four paired `LAB 3 TODO` regions covering ELF header fields, PMO creation, image copying, and VMR flags.

### Task 2: Migrate Lab1 Boot Annotations

**Files:**
- Modify: `kernel/arch/aarch64/boot/raspi3/init/mmu.c`
- Modify: `kernel/arch/aarch64/boot/raspi3/init/tools.S`
- Modify: `kernel/arch/aarch64/boot/raspi3/peripherals/uart.c`

**Interfaces:**
- Consumes: the corresponding files below `/Volumes/linux_code/OS-repo/OS-Course-Lab/Lab1`
- Produces: correctly bounded LAB 1 exercises 1–5 around the complete boot implementation

- [ ] **Step 1: Insert the LAB 1 boundaries and attached instructional comments**

Use `apply_patch` to place the exact source comments around the matching exception-level transition, UART output, MMU enable, and kernel page-table initialization statements. A resulting region must have this form:

```c
/* LAB 1 TODO 3 BEGIN */
/* Output each character through the UART implementation. */
complete_existing_implementation();
/* LAB 1 TODO 3 END */
```

The illustrative English line above is not added unless it exists in the student source; actual inserted text comes only from the source files.

- [ ] **Step 2: Verify Lab1 changes are comment-only**

Run:

```bash
git diff --check -- \
  kernel/arch/aarch64/boot/raspi3/init/mmu.c \
  kernel/arch/aarch64/boot/raspi3/init/tools.S \
  kernel/arch/aarch64/boot/raspi3/peripherals/uart.c
git diff --word-diff=porcelain -- \
  kernel/arch/aarch64/boot/raspi3/init/mmu.c \
  kernel/arch/aarch64/boot/raspi3/init/tools.S \
  kernel/arch/aarch64/boot/raspi3/peripherals/uart.c
```

Expected: no whitespace errors and only added comment tokens.

### Task 3: Migrate Lab2 Memory-Management Annotations

**Files:**
- Modify: `kernel/arch/aarch64/irq/pgfault.c`
- Modify: `kernel/arch/aarch64/mm/page_table.c`
- Modify: `kernel/mm/buddy.c`
- Modify: `kernel/mm/kmalloc.c`
- Modify: `kernel/mm/pgfault_handler.c`
- Modify: `kernel/mm/slab.c`
- Modify: `kernel/mm/vmspace.c`

**Interfaces:**
- Consumes: the corresponding files below `/Volumes/linux_code/OS-repo/OS-Course-Lab/Lab2`
- Produces: LAB 2 exercises 1–7 around allocator, page-table, page-fault, and VMR implementations

- [ ] **Step 1: Insert allocator annotations**

Use `apply_patch` to bound the complete implementations in `buddy.c`, `slab.c`, and `kmalloc.c` with their exact LAB 2 TODO comments and retain source hints attached to each region.

- [ ] **Step 2: Insert address-space and fault annotations**

Use `apply_patch` to annotate `page_table.c`, `pgfault.c`, `pgfault_handler.c`, and `vmspace.c`. Where one TODO exercise has multiple regions or internal hint comments, preserve every region and place each hint beside the implementation step it describes.

- [ ] **Step 3: Verify Lab2 changes are comment-only**

Run:

```bash
git diff --check -- kernel/arch/aarch64/irq/pgfault.c \
  kernel/arch/aarch64/mm/page_table.c kernel/mm/buddy.c \
  kernel/mm/kmalloc.c kernel/mm/pgfault_handler.c kernel/mm/slab.c \
  kernel/mm/vmspace.c
```

Expected: no whitespace errors; manual diff inspection shows only comment additions.

### Task 4: Migrate Lab3 Exception, Capability, and Root-Thread Annotations

**Files:**
- Modify: `kernel/arch/aarch64/irq/irq_entry.S`
- Modify: `kernel/arch/aarch64/sched/context.c`
- Modify: `kernel/object/cap_group.c`
- Modify: `kernel/object/thread.c`
- Modify: `user/system-services/chcore-libc/libchcore/porting/overrides/src/chcore-port/stdio.c` (the target of the `user/chcore-libc` symlink)

**Interfaces:**
- Consumes: current Lab3 annotation comments plus the canonical `thread.c` scaffold regions from commit `e41b376d`
- Produces: paired LAB 3 regions around exception entry/exit, context switch, capabilities, root-thread loading, and libc output

- [ ] **Step 1: Insert exception, context, capability, and libc annotations**

Use `apply_patch` to place every LAB 3 boundary and directly related explanation in the four files other than `thread.c`, using function and instruction anchors.

- [ ] **Step 2: Insert the four canonical root-thread regions**

Use `apply_patch` to add four paired regions in `kernel/object/thread.c`: ELF header-field extraction, PMO creation, embedded-image copy/setup, and VMR permission calculation. Do not reproduce the current student file's displaced extra `END` marker.

- [ ] **Step 3: Verify Lab3 boundaries**

Run:

```bash
rg -n -P '(?i)\bLAB\s*3\s+TODO\b' \
  kernel/arch/aarch64/irq/irq_entry.S \
  kernel/arch/aarch64/sched/context.c kernel/object/cap_group.c \
  kernel/object/thread.c \
  user/system-services/chcore-libc/libchcore/porting/overrides/src/chcore-port/stdio.c
```

Expected: each semantic region has one `BEGIN` and one `END`; `thread.c` has eight marker lines forming four pairs.

### Task 5: Migrate Lab4 Scheduler, Timer, IRQ, and IPC Annotations

**Files:**
- Modify: `kernel/arch/aarch64/plat/raspi3/irq/irq.c`
- Modify: `kernel/arch/aarch64/plat/raspi3/irq/timer.c`
- Modify: `kernel/ipc/connection.c`
- Modify: `kernel/irq/timer.c`
- Modify: `kernel/sched/policy_rr.c`
- Modify: `kernel/sched/sched.c`

**Interfaces:**
- Consumes: the corresponding files below `/Volumes/linux_code/OS-repo/OS-Course-Lab/Lab4`
- Produces: LAB 4 exercise regions around scheduling, interrupts, timers, and IPC implementations

- [ ] **Step 1: Insert scheduler and timer/IRQ annotations**

Use `apply_patch` to annotate the two scheduler files and three timer/IRQ files, retaining exercise numbering such as `(exercise 4 and exercise 6)` verbatim.

- [ ] **Step 2: Insert IPC annotations**

Use `apply_patch` to annotate all five LAB 4 exercise 7 regions in `kernel/ipc/connection.c`, including attached source hints.

- [ ] **Step 3: Verify Lab4 changes**

Run:

```bash
git diff --check -- kernel/arch/aarch64/plat/raspi3/irq/irq.c \
  kernel/arch/aarch64/plat/raspi3/irq/timer.c kernel/ipc/connection.c \
  kernel/irq/timer.c kernel/sched/policy_rr.c kernel/sched/sched.c
```

Expected: no whitespace errors and only comment additions.

### Task 6: Migrate Lab5 System-Service Annotations

**Files:**
- Modify: `user/system-services/system-servers/fsm/fsm.c`
- Modify: `user/system-services/system-servers/fsm/fsm_client_cap.c`
- Verify only: `user/system-services/system-servers/fs_base/fs_page_fault.c`
- Modify: `user/system-services/system-servers/fs_base/fs_vnode.c`
- Modify: `user/system-services/system-servers/fs_base/fs_wrapper.c`
- Modify: `user/system-services/system-servers/fs_base/fs_wrapper_ops.c`

**Interfaces:**
- Consumes: the corresponding files below `/Volumes/linux_code/OS-repo/OS-Course-Lab/Lab5`
- Produces: Lab 5 parts 1–4 around complete service implementations, plus an explicit unmapped report for LAB7 regions whose implementation is absent from the target

- [ ] **Step 1: Insert FSM annotations**

Use `apply_patch` to place Part 1 boundaries and related explanations in `fsm.c` and `fsm_client_cap.c`.

- [ ] **Step 2: Insert filesystem annotations and audit LAB7 mapping**

Use `apply_patch` to place Part 2–4 boundaries and related explanations in `fs_vnode.c`, `fs_wrapper.c`, and `fs_wrapper_ops.c`. Search `fs_page_fault.c` for `predict_prefetch_pages`, `fmap_area_count_fault`, and `usys_user_fault_map_batched`; because none of the LAB7 implementation exists in the target, leave that file unchanged and record both LAB7 regions as unmapped instead of inventing boundaries.

- [ ] **Step 3: Verify Lab5 changes**

Run:

```bash
git diff --check -- user/system-services/system-servers/fsm/fsm.c \
  user/system-services/system-servers/fsm/fsm_client_cap.c \
  user/system-services/system-servers/fs_base/fs_vnode.c \
  user/system-services/system-servers/fs_base/fs_wrapper.c \
  user/system-services/system-servers/fs_base/fs_wrapper_ops.c
```

Expected: no whitespace errors and only comment additions; `fs_page_fault.c` remains unchanged.

### Task 7: Prove Coverage and Preserve Executable Source

**Files:**
- Verify: the 26 modified code files from Tasks 2–6 and the one explicitly unmapped LAB7 file
- Verify: `docs/superpowers/specs/2026-08-07-lab-todo-comment-migration-design.md`
- Verify: `docs/superpowers/plans/2026-08-07-lab-todo-comment-migration.md`

**Interfaces:**
- Consumes: the complete migration diff
- Produces: an auditable comment-only diff and a final coverage report

- [ ] **Step 1: Check formatting and changed-file scope**

Run:

```bash
git diff --check
git status --short
git diff --name-only c21922a
```

Expected: no diff errors; only the plan and the 26 mapped target files are new or modified after `c21922a`. The unmapped `fs_page_fault.c` is absent from the diff.

- [ ] **Step 2: Check marker pairing**

Run a per-file count of LAB TODO `BEGIN` and `END` markers over all modified code files.

Expected: counts match in every file; `kernel/object/thread.c` contains four canonical pairs rather than the displaced extra marker in the filled student copy.

- [ ] **Step 3: Inspect every changed hunk**

Run:

```bash
git diff --word-diff=porcelain c21922a -- '*.c' '*.h' '*.S' '*.ld'
```

Expected: every addition is comment syntax or comment text; no executable token is removed or added.

- [ ] **Step 4: Run a build-neutral syntax safeguard**

Because comment-only changes do not require relinking to validate behavior, run the repository's existing formatting-independent diff checks rather than altering generated build state.

Run:

```bash
git diff --check c21922a
```

Expected: exit status 0.

- [ ] **Step 5: Commit the migration**

Run:

```bash
git add docs/superpowers/plans/2026-08-07-lab-todo-comment-migration.md \
  kernel user
git commit -m "docs: annotate complete sources with lab TODO regions"
```

Expected: one commit containing the plan and comment-only source annotations.
