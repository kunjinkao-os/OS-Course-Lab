CHBUILD ?= ./chbuild
PLATFORM ?= raspi3

.DEFAULT_GOAL := all

.PHONY: all defconfig build qemu qemu-gdb qemu-gdb-stop clean distclean help

all: build

defconfig:
	$(CHBUILD) defconfig $(PLATFORM)

.config:
	$(CHBUILD) defconfig $(PLATFORM)

build: .config
	$(CHBUILD) build

qemu: build
	$(CHBUILD) run

qemu-gdb:
	$(CHBUILD) debug

qemu-gdb-stop:
	$(CHBUILD) debug-stop

clean:
	$(CHBUILD) clean

distclean:
	$(CHBUILD) distclean

help:
	@printf '%s\n' \
		'make              configure Raspi3 if needed, then build ChCore' \
		'make qemu         build ChCore, then boot it in QEMU' \
		'make qemu-gdb     build a debug kernel, then wait for VS Code/GDB' \
		'make qemu-gdb-stop stop the active QEMU debug session' \
		'make defconfig    generate the default config for PLATFORM (default: raspi3)' \
		'make clean        remove build output and retain .config' \
		'make distclean    remove build output and .config'
