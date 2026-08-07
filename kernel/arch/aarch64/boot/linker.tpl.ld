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

/*
 * This file will be firstly configured by CMake to fill in `init_objects`,
 * then preprocessed by C compiler to fill in some definitions from `image.h`.
 */

// image.h 展开：KERNEL_VADDR=0xffffff0000000000，TEXT_OFFSET=0x80000。
#include "image.h"

// ========== 内核启动：Phase 1: 固件装载与镜像布局 (Step 1) ==========
// [Step 1.1] 树莓派固件按 config.txt 以 AArch64 模式把 kernel8.img 装到物理地址 0x80000，入口为 _start。
ENTRY(_start)

SECTIONS
{
    . = TEXT_OFFSET;

    // [Step 1.2] init_objects 是 MMU 开启前使用的低地址启动代码、数据、栈和页表。
    img_start = .;
    init : {
        ${init_objects}
    }
    . = ALIGN(4K);
    init_end = ABSOLUTE(.);

    // [Step 1.3] 正式内核按高半区虚拟地址链接，但物理装载位置仍紧跟 init 段；TTBR1 稍后建立两者的映射。
    .text KERNEL_VADDR + init_end : AT(init_end) {
    _text_start = .;
        *(.text*)
    }
    . = ALIGN(4K);
    _text_end = .;

    .data : {
        *(.data*)
    }
    . = ALIGN(4K);

    .rodata : {
        *(.rodata*)
        . = ALIGN(4K);
        ${incbin_linker_script}
    }
    . = ALIGN(4K);
    _edata = . - KERNEL_VADDR;

    // BSS 边界转成物理地址，供 MMU 开启前的 init_c 清零。
    _bss_start = . - KERNEL_VADDR;
    .bss : {
        *(.bss*)
    }
    . = ALIGN(4K);
    _bss_end = . - KERNEL_VADDR;

    _extable_start = .;
    .extable : {
        *(.extable*)
    }
    . = ALIGN(4K);
    _extable_end = .;
    
    img_end = . - KERNEL_VADDR;

    /DISCARD/ : { *(.comment) *(.gnu*) *(.note*) *(.eh_frame*) }
}
