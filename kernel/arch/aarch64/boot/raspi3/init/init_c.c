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

// boot.h 声明链接符号和后续入口；image.h/consts.h 提供地址布局、4 KiB 启动栈等常量。
#include "boot.h"
#include "image.h"
#include "consts.h"

#include <common/types.h>

// ========== 内核启动：Phase 4: 建立最小 C 运行环境 (Step 4) ==========
char boot_cpu_stack[PLAT_CPU_NUMBER][INIT_STACK_SIZE] ALIGN(4096);

/*
 * Initialize these varibles in order to make them not in .bss section.
 * So, they will have concrete initial value even on real machine.
 *
 * Non-primary CPUs will spin until they see the secondary_boot_flag becomes
 * non-zero which is set in kernel (see enable_smp_cores).
 *
 * The secondary_boot_flag is initilized as {NOT_BSS, 0, 0, ...}.
 */
#define NOT_BSS (0xBEEFUL)
long secondary_boot_flag[PLAT_CPU_NUMBER] = {NOT_BSS};
volatile u64 clear_bss_flag = NOT_BSS;

/* Uart */
void early_uart_init(void);
void uart_send_string(char *);

static void wakeup_other_cores(void)
{
	u64 *addr;

	// [Step 4.4] 把 CPU1~3 的固件固定入口槽 0xe0/0xe8/0xf0 都写为 0x80000，再用 SEV 唤醒次核。
	// addr = (u64 *)0xd8;
	// *addr = TEXT_OFFSET;
	addr = (u64 *)0xe0;
	*addr = TEXT_OFFSET;
	addr = (u64 *)0xe8;
	*addr = TEXT_OFFSET;
	addr = (u64 *)0xf0;
	*addr = TEXT_OFFSET;

	/*
	 * Instruction sev (set event) for waking up other (non-primary) cores
	 * that executes wfe instruction.
	 */
	asm volatile("sev");
}

static void clear_bss(void)
{
	u64 bss_start_addr;
	u64 bss_end_addr;
	u64 i;

	// [Step 4.2] 按链接脚本给出的物理边界逐字节清零正式内核 BSS，随后写 0 释放等待中的次核。
	bss_start_addr = (u64)&_bss_start;
	bss_end_addr = (u64)&_bss_end;

	for (i = bss_start_addr; i < bss_end_addr; ++i)
		*(char *)i = 0;

	clear_bss_flag = 0;
}

void init_c(void)
{
	// [Step 4.2] 先进入 clear_bss，建立 C 未初始化全局变量应为 0 的运行环境。
	clear_bss();

	// [Step 4.3] 进入 uart.c 初始化早期串口；MMU 未开，因此使用 0x3f... 物理 MMIO 地址。
	early_uart_init();
	uart_send_string("boot: init_c\r\n");

	// [Step 4.4] 进入 wakeup_other_cores，使 CPU1~3 从 start.S 开始执行并停在 SMP boot flag 上。
	wakeup_other_cores();

	// ========== 内核启动：Phase 5: 构造启动页表 (Step 5) ==========
	// [Step 5.1] 进入 mmu.c，填充 TTBR0 低地址恒等映射和 TTBR1 高半区映射。
	uart_send_string("[BOOT] Install kernel page table\r\n");
	init_kernel_pt();

	// ========== 内核启动：Phase 6: 安装启动页表并开启 MMU (Step 6) ==========
	// [Step 6.1] 进入 tools.S 安装 MAIR/TCR/TTBR 并置 SCTLR_EL1.M；返回时 MMU 和缓存已开启。
	el1_mmu_activate();
	uart_send_string("[BOOT] Enable el1 MMU\r\n");

	// ========== 内核启动：Phase 7: 切入高半区正式内核 (Step 7) ==========
	uart_send_string("[BOOT] Jump to kernel main\r\n");
	// [Step 7.1] 调用高地址 start_kernel，并把次核 boot flag 地址作为 main 的第一个参数继续传递；
	// 因目标超出 BL 的直接范围，链接器会插入低地址 veneer，由 veneer 用 BR 完成真正的高地址跳转。
	start_kernel(secondary_boot_flag);

	/* Never reach here */
}

void secondary_init_c(int cpuid)
{
	el1_mmu_activate();
	secondary_cpu_boot(cpuid);
}
