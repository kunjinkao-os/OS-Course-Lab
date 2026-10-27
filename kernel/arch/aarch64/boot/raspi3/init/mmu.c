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

// macro.h 提供 BUG_ON；其余头文件展开高半区基址、链接边界、CPU 数和启动栈大小。
#include <common/macro.h>
#include "image.h"
#include "boot.h"
#include "consts.h"

typedef unsigned long u64;
typedef unsigned int u32;

// ========== 内核启动：Phase 5: 构造启动页表 (Step 5) ==========
// [Step 5.1] Raspi3 启动物理布局：0~0x3f000000 为普通内存，0x3f000000~1 GiB 为设备窗口。
#define PHYSMEM_START   (0x0UL)
#define PERIPHERAL_BASE (0x3F000000UL)
#define PHYSMEM_END     (0x40000000UL)

/* The number of entries in one page table page */
#define PTP_ENTRIES 512
/* The size of one page table page */
#define PTP_SIZE 4096
#define ALIGN(n) __attribute__((__aligned__(n)))
// 每张表占 4 KiB、含 512 个 8 字节描述符；L0/L1/L2/L3 单项分别覆盖 512 GiB/1 GiB/2 MiB/4 KiB。
// TTBR0 四级表提供 VA=PA 的临时低地址映射，TTBR1 四级表提供 VA=KERNEL_VADDR+PA 的正式高半区映射。
u64 boot_ttbr0_l0[PTP_ENTRIES] ALIGN(PTP_SIZE);
u64 boot_ttbr0_l1[PTP_ENTRIES] ALIGN(PTP_SIZE);
u64 boot_ttbr0_l2[PTP_ENTRIES] ALIGN(PTP_SIZE);
u64 boot_ttbr0_l3[PTP_ENTRIES] ALIGN(PTP_SIZE);

u64 boot_ttbr1_l0[PTP_ENTRIES] ALIGN(PTP_SIZE);
u64 boot_ttbr1_l1[PTP_ENTRIES] ALIGN(PTP_SIZE);
u64 boot_ttbr1_l2[PTP_ENTRIES] ALIGN(PTP_SIZE);
u64 boot_ttbr1_l3[PTP_ENTRIES] ALIGN(PTP_SIZE);

// 描述符当前取值：VALID=有效；TABLE/PTE 区分下级表或末级页；PXN/UXN 禁止 EL1/EL0 执行；
// AF 表示已访问，nG 表示非全局，SH=0b11 表示 Inner Shareable，AttrIndx=4/0 分别选择普通 WBWA/设备 nGnRnE，
// AP=0b10 表示 EL1 只读且 EL0 不可访问。这些位共同表达页表项的地址、内存类型、权限和共享属性。
#define IS_VALID (1UL << 0)
#define IS_TABLE (1UL << 1)
#define IS_PTE (1UL << 1)

#define PXN            (0x1UL << 53)
#define UXN            (0x1UL << 54)
#define ACCESSED       (0x1UL << 10)
#define NG             (0x1UL << 11)
#define INNER_SHARABLE (0x3UL << 8)
#define NORMAL_MEMORY  (0x4UL << 2)
#define DEVICE_MEMORY  (0x0UL << 2)
#define RDONLY_S       (0x2UL << 6)

#define SIZE_2M (2UL * 1024 * 1024)
#define SIZE_4K (4UL * 1024)

#define GET_L0_INDEX(x) (((x) >> (12 + 9 + 9 + 9)) & 0x1ff)
#define GET_L1_INDEX(x) (((x) >> (12 + 9 + 9)) & 0x1ff)
#define GET_L2_INDEX(x) (((x) >> (12 + 9)) & 0x1ff)
#define GET_L3_INDEX(x) (((x) >> (12)) & 0x1ff)

extern int boot_cpu_stack[PLAT_CPU_NUMBER][INIT_STACK_SIZE];

void init_kernel_pt(void)
{
        u64 vaddr = PHYSMEM_START;

        // [Step 5.2] 构造 TTBR0：L0→L1→L2；前 2 MiB 再下钻 L3 以 4 KiB 页保护 init 代码和可写启动栈，
        // 其余普通内存和外设窗口用 2 MiB 块恒等映射。低地址项置 nG，供 MMU 刚开启后的 init_c 临时使用。
        boot_ttbr0_l0[GET_L0_INDEX(vaddr)] = ((u64)boot_ttbr0_l1) | IS_TABLE
                                             | IS_VALID | NG;
        boot_ttbr0_l1[GET_L1_INDEX(vaddr)] = ((u64)boot_ttbr0_l2) | IS_TABLE
                                             | IS_VALID | NG;

	boot_ttbr0_l2[GET_L2_INDEX(vaddr)] = ((u64)boot_ttbr0_l3) | IS_TABLE
                                             | IS_VALID | NG;

        /* first 2M, including .init section */
        /*
         * 首次 2 MiB 范围的映射，使用 L3 级别的 4 KiB 页粒度进行映射。
         * 目的是对 init 段（和启动栈）做更精细的权限控制（只读/可写），
         * 而不是用 2 MiB 的大块映射覆盖掉这些需要细粒度保护的页面。
         */
        for (; vaddr < SIZE_2M; vaddr += SIZE_4K) {
                boot_ttbr0_l3[GET_L3_INDEX(vaddr)] =
                        (vaddr)
                        | UXN /* Unprivileged execute never */
                        | PXN /* Privileged execute never */
                        | ACCESSED /* Set access flag */
                        | NG /* Mark as not global */
                        | INNER_SHARABLE /* Sharebility */
                        | NORMAL_MEMORY /* Normal memory */
                        | IS_PTE
                        | IS_VALID;
                
                /*
                 * init 段（img_start~init_end）中的代码由于 WXN 要映射为只读。
                 * 注意：boot_cpu_stack 也位于 init 段，但启动栈需要写权限，
                 * 因此对启动栈所在页做例外处理，保留写权限。
                 */
                if (vaddr >= (u64)(&img_start) && vaddr < (u64)(&init_end) && 
                        (vaddr < (u64)boot_cpu_stack || vaddr >= ((u64)boot_cpu_stack) + PLAT_CPU_NUMBER * INIT_STACK_SIZE)) {
                        boot_ttbr0_l3[GET_L3_INDEX(vaddr)] &= ~PXN;
                        boot_ttbr0_l3[GET_L3_INDEX(vaddr)] |= RDONLY_S; /* Read Only*/
                }
        }

        /* Normal memory: PHYSMEM_START ~ PERIPHERAL_BASE */
        /* Map with 2M granularity */
        /*
         * 对于低地址的普通内存区域，使用 L2 条目以 2 MiB 为单位做恒等映射（va = pa），
         * 这样可以减少页表占用并提高 TLB 命中率。此处仍然把条目标记为非全局（nG），
         * 因为这是给刚启用 MMU 的临时 TTBR0 使用的映射。
         */
        for (; vaddr < PERIPHERAL_BASE; vaddr += SIZE_2M) {
                boot_ttbr0_l2[GET_L2_INDEX(vaddr)] =
                        (vaddr) /* low mem, va = pa */
                        | UXN /* Unprivileged execute never */
                        | ACCESSED /* Set access flag */
                        | NG /* Mark as not global */
                        | INNER_SHARABLE /* Sharebility */
                        | NORMAL_MEMORY /* Normal memory */
                        | IS_VALID;
        }

        /* Peripheral memory: PERIPHERAL_BASE ~ PHYSMEM_END */
        /* Map with 2M granularity */
        /*
         * 外设区使用 Device memory 属性并以 2 MiB 粒度映射，确保访问不会被缓存
         *（或使用 device 类型的内存属性），以满足 MMIO 语义。
         */
        for (vaddr = PERIPHERAL_BASE; vaddr < PHYSMEM_END; vaddr += SIZE_2M) {
                boot_ttbr0_l2[GET_L2_INDEX(vaddr)] =
                        (vaddr) /* low mem, va = pa */
                        | UXN /* Unprivileged execute never */
                        | ACCESSED /* Set access flag */
                        | NG /* Mark as not global */
                        | DEVICE_MEMORY /* Device memory */
                        | IS_VALID;
        }

        // [Step 5.3] 构造 TTBR1（内核页表地址空间）：把物理 0~1 GiB 映射到 KERNEL_VADDR 起的高半区；前 2 MiB 用 L3 页，
        // 其中正式 .text 设置为 EL1 只读可执行，其余页可写不可执行；后续普通内存和设备区用 2 MiB 块映射。
        // 高半区项不置 nG，作为所有地址空间共享的全局内核映射。
        /* LAB 1 TODO 5 BEGIN */
        /* Step 1: set L0 and L1 page table entry */
        /* BLANK BEGIN */
        vaddr = KERNEL_VADDR + PHYSMEM_START;
        boot_ttbr1_l0[GET_L0_INDEX(vaddr)] = ((u64)boot_ttbr1_l1) | IS_TABLE
                                             | IS_VALID;
        boot_ttbr1_l1[GET_L1_INDEX(vaddr)] = ((u64)boot_ttbr1_l2) | IS_TABLE
                                             | IS_VALID;
        /* BLANK END */

        /* Step 2: map PHYSMEM_START ~ PERIPHERAL_BASE with 2MB granularity */
        /* BLANK BEGIN */
        /* Normal memory: PHYSMEM_START ~ PERIPHERAL_BASE
	 * The text section code in kernel should be mapped with flag R/X.
	 * The other section and normal memory is mapped with flag R/W.
         * memory layout :
         * | normal memory | kernel text section | kernel data section ... | normal memory |
         */


        boot_ttbr1_l2[GET_L2_INDEX(vaddr)] = ((u64)boot_ttbr1_l3) | IS_TABLE
                                             | IS_VALID;

	/* the kernel text section was mapped in the first 
	 * L2 page table in boot_ptd_l1 now.
	 */
        BUG_ON((u64)(&_text_end) >= KERNEL_VADDR + SIZE_2M);
        /* _text_start & _text_end should be 4K aligned*/
        BUG_ON((u64)(&_text_start) % SIZE_4K != 0 || (u64)(&_text_end) % SIZE_4K != 0);

        for (; vaddr < KERNEL_VADDR + SIZE_2M; vaddr += SIZE_4K) {
                boot_ttbr1_l3[GET_L3_INDEX(vaddr)] =
                        (vaddr - KERNEL_VADDR)
                        | UXN /* Unprivileged execute never */
                        | PXN /* Priviledged execute never*/
                        | ACCESSED /* Set access flag */
                        | INNER_SHARABLE /* Sharebility */
                        | NORMAL_MEMORY /* Normal memory */
                        | IS_PTE
                        | IS_VALID;
                /* (KERNEL_VADDR + TEXT_START ~ KERNEL_VADDR + TEXT_END) was mapped to 
                * physical address (PHY_START ~ PHY_START + TEXT_END) with R/X
                */
                if (vaddr >= (u64)(&_text_start) && vaddr < (u64)(&_text_end)) {
                        boot_ttbr1_l3[GET_L3_INDEX(vaddr)] &= ~PXN;
                        boot_ttbr1_l3[GET_L3_INDEX(vaddr)] |= RDONLY_S; /* Read Only*/
                }
        }

        for (; vaddr < KERNEL_VADDR + PERIPHERAL_BASE; vaddr += SIZE_2M) {
                /* No NG bit here since the kernel mappings are shared */
                boot_ttbr1_l2[GET_L2_INDEX(vaddr)] =
                        (vaddr - KERNEL_VADDR) /* high mem, va = kbase + pa */
                        | UXN /* Unprivileged execute never */
                        | PXN /* Priviledged execute never*/
                        | ACCESSED /* Set access flag */
                        | INNER_SHARABLE /* Sharebility */
                        | NORMAL_MEMORY /* Normal memory */
                        | IS_VALID;
        }
        /* BLANK END */

        /* Step 2: map PERIPHERAL_BASE ~ PHYSMEM_END with 2MB granularity */
        /* BLANK BEGIN */
        /* Peripheral memory: PERIPHERAL_BASE ~ PHYSMEM_END */
        /* Map with 2M granularity */
        for (vaddr = KERNEL_VADDR + PERIPHERAL_BASE;
             vaddr < KERNEL_VADDR + PHYSMEM_END;
             vaddr += SIZE_2M) {
                boot_ttbr1_l2[GET_L2_INDEX(vaddr)] =
                        (vaddr - KERNEL_VADDR) /* high mem, va = kbase + pa */
                        | UXN /* Unprivileged execute never */
                        | PXN /* Priviledged execute never*/
                        | ACCESSED /* Set access flag */
                        | DEVICE_MEMORY /* Device memory */
                        | IS_VALID;
        }
        /* BLANK END */
        /* LAB 1 TODO 5 END */

        // [Step 5.4] 最后用一个 1 GiB 的 L1 设备块映射 0x40000000 起的本地外设区，供定时器、IRQ 和 mailbox 使用。
        vaddr = KERNEL_VADDR + PHYSMEM_END;
        boot_ttbr1_l1[GET_L1_INDEX(vaddr)] = PHYSMEM_END | UXN /* Unprivileged
                                                                  execute never
                                                                */
                                             | PXN      /* Priviledged execute never*/
                                             | ACCESSED /* Set access flag */
                                             | DEVICE_MEMORY /* Device memory */
                                             | IS_VALID;
}
