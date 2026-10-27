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

// common/asm.h 展开函数宏；common/vars.h 提供 4 KiB 正式内核栈大小和高半区基址。
#include <common/asm.h>
#include <common/vars.h>

.extern empty_page

// ========== 内核启动：Phase 7: 切入高半区正式内核 (Step 7) ==========
// x0/x1 按 AArch64 调用约定继续传给 main；Raspi3 只使用 x0 中的次核 boot flag。
BEGIN_FUNC(start_kernel)

    // [Step 7.2] 切换到 CPU0 的高地址正式栈，暂存 main 参数；再把 TTBR0 换成全零空表，彻底废弃低地址恒等映射。
    ldr     x2, =cpu_stacks
    add     x2, x2, CPU_STACK_SIZE
    mov     sp, x2

    /* Save x0 and x1 */
    stp x0, x1, [sp, #-16]!

    /*
     * Make sure that no translation based
     * on boot page table can happen.
     */
    adrp    x2, empty_page
    msr     ttbr0_el1, x2
    isb

    // [Step 7.3] 调用 mm/tlb.c 的 flush_tlb_all，清除所有可能命中旧 TTBR0 页表的缓存翻译。
    bl flush_tlb_all

    /* Restore x0 and x1 */
    //main的两个参数
    ldp x0, x1, [sp], #16

    // [Step 7.4] 恢复参数后调用内核 main；按执行时序转到 main.c 的 Phase 8。
    bl      main
END_FUNC(start_kernel)

BEGIN_FUNC(secondary_cpu_boot)
    mov     x19, x0

    mov     x1, #CPU_STACK_SIZE
    mul     x2, x0, x1
    ldr     x3, =cpu_stacks
    add     x2, x2, x3
    add     x2, x2, CPU_STACK_SIZE
    mov     sp, x2

    /*
     * Make sure that no translation based
     * on boot page table can happen.
     */
    adrp    x3, empty_page
    msr     ttbr0_el1, x3
    isb
    /*  
     * Call flush_tlb_all here to flush all the cached TLBs for
     * the boot time TTBR0_EL1.
     */
    bl      flush_tlb_all

    mov     x0, x19
    bl      secondary_start
END_FUNC(secondary_cpu_boot)
