CHBUILD ?= ./chbuild
PLATFORM ?= raspi3
CONFIG ?= .config

.DEFAULT_GOAL := all

.PHONY: all defconfig build qemu clean distclean help

all: build

defconfig:
	$(CHBUILD) defconfig $(PLATFORM)

$(CONFIG):
	$(CHBUILD) defconfig $(PLATFORM)

build: $(CONFIG)
	$(CHBUILD) build

qemu: build
	$(CHBUILD) run

clean:
	$(CHBUILD) clean

distclean:
	$(CHBUILD) distclean

help:
	@printf '%s\n' \
		'make              configure Raspi3 if needed, then build ChCore' \
		'make qemu         build ChCore, then boot it in QEMU' \
		'make defconfig    generate the default config for PLATFORM (default: raspi3)' \
		'make clean        remove build output and retain .config' \
		'make distclean    remove build output and .config'
