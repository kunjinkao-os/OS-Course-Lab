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

#include <common/types.h>
#include <common/errno.h>
#include <common/macro.h>
#include <common/lock.h>
#include <common/kprint.h>
#include <arch/sync.h>

#include "ticket.h"

int lock_init(struct lock *l)
{
        //这里进行类型转换，会将u64抽象的lock转为lock_impl
	struct lock_impl *lock = (struct lock_impl *)l;
	BUG_ON(!lock);
	/* Initialize ticket lock */
        /*采用票锁*/
        //owner表示当前轮到谁
	lock->owner = 0;
        //next表示下一个进来的线程拿到的票号
	lock->next = 0;
        smp_wmb();
	return 0;
}

void lock(struct lock *l)
{

        struct lock_impl *lock = (struct lock_impl *)l;
        u32 lockval = 0, newval = 0, ret = 0;

        BUG_ON(!lock);
        /*
        先对 next 做原子递增，给当前正在执行 lock 的线程发一个唯一的票号。
        然后不断读取 owner。
        只有当 owner == 自己拿到的票号 时，才算真正获得锁。
        */
        asm volatile(
                "       prfm    pstl1strm, %3\n"
                "1:     ldaxr   %w0, %3\n"
                "       add     %w1, %w0, #0x1\n"
                "       stxr    %w2, %w1, %3\n"
                "       cbnz    %w2, 1b\n"
                "2:     ldar    %w2, %4\n"
                "       cmp     %w0, %w2\n"
                "       b.ne    2b\n"
                : "=&r"(lockval), "=&r" (newval), "=&r"(ret), "+Q" (lock->next)
                : "Q" (lock->owner)
                : "memory");
}

// clang-format off
//核心判断条件是：owner == next 才说明锁空闲。
int try_lock(struct lock *l)
{

/*
它的执行流程大致是：

用 ldaxr 原子读出当前的 next
用 ldar 读出当前的 owner
先比较 owner 和 next
如果不相等，说明锁已经被占用，直接失败，返回 -1
如果相等，说明锁空闲，再把 next 原子加 1，表示自己拿到这个锁
如果 stxr 写回失败，说明别的 CPU 抢先改了 next，就重试
成功后执行 dmb ish，保证后续临界区内的读写不会跑到加锁前面去
返回 0 表示成功
所以它和普通 lock() 的区别在于：

lock() 会一直等，直到轮到自己
try_lock() 不等，抢不到就立刻返回失败
*/
        struct lock_impl *lock = (struct lock_impl *)l;
        u32 lockval = 0, newval = 0, ret = 0, ownerval = 0;


        BUG_ON(!lock);
        asm volatile(
                        "       prfm    pstl1strm, %4\n"
                        "1:     ldaxr   %w0, %4\n"
                        "       ldar    %w3, %5\n"
                        "       add     %w1, %w0, #0x1\n"
                        "       cmp     %w0, %w3\n"
                        "       b.ne    2f\n" /* fail */
                        "       stxr    %w2, %w1, %4\n"
                        "       cbnz    %w2, 1b\n" /* retry */
                        "       mov     %w2, #0x0\n" /* success */
                        "       dmb     ish\n" /* store -> load/store barrier */
                        "       b       3f\n"
                        "2:     mov     %w2, #0xffffffffffffffff\n" /* fail */
                        "3:\n"
                        : "=&r"(lockval), "=&r" (newval), "=&r"(ret),
                        "=&r"(ownerval), "+Q" (lock->next)
                        : "Q" (lock->owner)
                        : "memory");
        return ret;
}
// clang-format on

void unlock(struct lock *l)
{
        struct lock_impl *lock = (struct lock_impl *)l;

        BUG_ON(!lock);
        smp_mb();       /* load, store -> store barrier may use stlr here */
        lock->owner = lock->owner + 1;
}

/*
next 表示已经发出去的票号总数
owner 表示已经轮到的票号
只要 next 比 owner 大，说明至少有一个线程已经拿到票，但还没轮到它执行
这时锁就不能算空闲，所以可以认为锁已经被一个线程所持有
*/
int is_locked(struct lock *l)
{
        struct lock_impl *lock = (struct lock_impl *)l;

        return lock->owner < lock->next;
}
