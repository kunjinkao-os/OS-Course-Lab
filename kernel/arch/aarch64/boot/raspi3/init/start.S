/*
 * Copyright (c) 2023 Institute of Parallel And Distributed Systems (IPADS), Shanghai Jiao Tong University (SJTU)
 * Licensed under the Mulan PSL v2.
 * You can use this software according to the terms and conditions of the Mulan PSL v2.
 * You may obtain a copy of Mulan PSL v2 at:
 *     http://license.coscl.org.cn/MulanPSL2
 * THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT, MERCHANTABILITY OR FIT FOR A PARTICULAR
 * PURPOSE.
 * See the Mulan PSL v2 for more details.
 */

// consts.h 提供 4 KiB 临时栈大小；common/asm.h 展开函数符号声明宏 BEGIN_FUNC/END_FUNC。
#include "consts.h"
#include <common/asm.h>

.extern arm64_elX_to_el1
.extern boot_cpu_stack
.extern secondary_boot_flag
.extern secondary_init_c
.extern clear_bss_flag
.extern init_c

// ========== 内核启动：Phase 2: 复位入口与多核分流 (Step 2) ==========
BEGIN_FUNC(_start)
	// [Step 2.1] 从 MPIDR_EL1 取得核号：CPU0 跳到 primary，CPU1~3 留在次核等待路径。
	mrs	x8, mpidr_el1
	and	x8, x8,	#0xFF
	cbz	x8, primary

	// [Step 2.2] 次核先等待主核清完 BSS，再切到 EL1、设置各自临时栈，并等待 main 放行 SMP。
wait_for_bss_clear:
	adr	x0, clear_bss_flag
	ldr	x1, [x0]
	cmp     x1, #0
	bne	wait_for_bss_clear

	/* Set cntkctl_el1 to enable cntvct_el0.
         * Enable it when you need to get current tick
         * at EL0, e.g. Running aarch64 ROS2 demos
	mov	x10, 0b11
	msr	cntkctl_el1, x10 */

	bl 	arm64_elX_to_el1

	/* Prepare stack pointer and jump to C. */
	mov	x1, #INIT_STACK_SIZE
	mul	x1, x8, x1
	adr 	x0, boot_cpu_stack
	add	x0, x0, x1
	add	x0, x0, #INIT_STACK_SIZE
	mov	sp, x0

wait_until_smp_enabled:
	/* CPU ID should be stored in x8 from the first line */
	mov	x1, #8
	mul	x2, x8, x1
	ldr	x1, =secondary_boot_flag
	add	x1, x1, x2
	ldr	x3, [x1]
	cbz	x3, wait_until_smp_enabled

	// 主核进入 main 并写 boot flag 后，次核才跳入 secondary_init_c；这已超出主核启动主线。
	mov	x0, x8
	b 	secondary_init_c

	/* Should never be here */
	b	.

primary:

	// [Step 2.3] 主核调用 arm64_elX_to_el1；按执行时序转到 tools.S 的 Phase 3。
	bl 	arm64_elX_to_el1

	// ========== 内核启动：Phase 4: 建立临时栈并进入 C (Step 4) ==========
	// [Step 4.1] EL1 返回后把 SP 指向 CPU0 的 4 KiB 低地址启动栈顶，再直接跳到 init_c。
	adr 	x0, boot_cpu_stack
	add 	x0, x0, #INIT_STACK_SIZE
	mov 	sp, x0

	b 	init_c

	/* Should never be here */
	b	.
END_FUNC(_start)
