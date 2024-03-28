##--------------------------------------------------------------------------------------------------
## Optional, user-provided configuration values
##--------------------------------------------------------------------------------------------------

# Default to the RPi4.
BSP ?= rpi4

# Default to a serial device name that is common in Linux.
DEV_SERIAL ?= /dev/ttyUSB0

OUT_BIN ?= ./kernel8.img # NOTE: should be generate automatical by your script
##--------------------------------------------------------------------------------------------------
## BSP-specific configuration values
##--------------------------------------------------------------------------------------------------
QEMU_MISSING_STRING = "This board is not yet supported for QEMU."

ifeq ($(BSP),rpi4)
    TARGET            = aarch64-unknown-none-softfloat
	KERNEL_BIN		  := $(OUT_BIN)
    OBJDUMP_BINARY    = aarch64-none-elf-objdump
    NM_BINARY         = aarch64-none-elf-nm
    READELF_BINARY    = aarch64-none-elf-readelf
    # OPENOCD_ARG       = -f /openocd/tcl/interface/ftdi/olimex-arm-usb-tiny-h.cfg -f /openocd/rpi4.cfg
    OPENOCD_ARG       = -f /openocd/tcl/interface/jlink.cfg -f /openocd/rpi4.cfg
    # JTAG_BOOT_IMAGE   = tools/raspi4/X1_JTAG_boot/jtag_boot_rpi4.img
	JTAG_BOOT_IMAGE   := $(OUT_BIN)
    RUSTC_MISC_ARGS   = -C target-cpu=cortex-a72
endif

EXEC_MINIPUSH      = ruby ./serial/minipush.rb

##------------------------------------------------------------------------------
## Dockerization
##------------------------------------------------------------------------------
DOCKER_CMD            = sudo docker run -t --rm -v $(shell pwd):/work/tutorial -w /work/tutorial
DOCKER_CMD_INTERACT   = $(DOCKER_CMD) -i
DOCKER_ARG_DIR_COMMON = -v $(shell pwd)/tools/raspi4/common:/work/common
DOCKER_ARG_DIR_JTAG   = -v $(shell pwd)/tools/raspi4/X1_JTAG_boot:/work/X1_JTAG_boot
DOCKER_ARG_DEV        = --privileged -v /dev:/dev
DOCKER_ARG_NET        = --network host

# DOCKER_IMAGE defined in include file (see top of this file).
DOCKER_GDB   = $(DOCKER_CMD_INTERACT) $(DOCKER_ARG_NET) $(DOCKER_IMAGE)

# Dockerize commands, which require USB device passthrough, only on Linux.
ifeq ($(shell uname -s),Linux)
    DOCKER_CMD_DEV = $(DOCKER_CMD_INTERACT) $(DOCKER_ARG_DEV)
    DOCKER_CHAINBOOT = $(DOCKER_CMD_DEV) $(DOCKER_ARG_DIR_COMMON) $(DOCKER_IMAGE)
    DOCKER_JTAGBOOT  = $(DOCKER_CMD_DEV) $(DOCKER_ARG_DIR_COMMON) $(DOCKER_ARG_DIR_JTAG) $(DOCKER_IMAGE)
    DOCKER_OPENOCD   = $(DOCKER_CMD_DEV) $(DOCKER_ARG_NET) $(DOCKER_IMAGE)
else
    DOCKER_OPENOCD   = echo "Not yet supported on non-Linux systems."; \#
endif

##--------------------------------------------------------------------------------------------------
## Targets
##--------------------------------------------------------------------------------------------------
.PHONY: all chainboot

all: $(KERNEL_BIN)

##------------------------------------------------------------------------------
## Push the kernel to the real HW target
##------------------------------------------------------------------------------
chainboot: $(KERNEL_BIN)
	@$(DOCKER_CHAINBOOT) $(EXEC_MINIPUSH) $(DEV_SERIAL) $(KERNEL_BIN)


##--------------------------------------------------------------------------------------------------
## Debugging targets
##--------------------------------------------------------------------------------------------------
.PHONY: jtagboot openocd gdb gdb-opt0

##------------------------------------------------------------------------------
## Push the JTAG boot image to the real HW target
##------------------------------------------------------------------------------
jtagboot: $(KERNEL_BIN)
	@$(DOCKER_JTAGBOOT) $(EXEC_MINIPUSH) $(DEV_SERIAL) $(JTAG_BOOT_IMAGE)

##------------------------------------------------------------------------------
## Start OpenOCD session
##------------------------------------------------------------------------------
openocd:
	$(call color_header, "Launching OpenOCD")
	@$(DOCKER_OPENOCD) openocd $(OPENOCD_ARG)

##------------------------------------------------------------------------------
## Start GDB session
##------------------------------------------------------------------------------
KERNEL_ELF := $(patsubst %.bin,%.elf,$(KERNEL_BIN))
gdb: RUSTC_MISC_ARGS += -C debuginfo=2
gdb: $(KERNEL_ELF)
	$(call color_header, "Launching GDB kernel: $(KERNEL_ELF)")
	@$(DOCKER_GDB) gdb-multiarch -q $(KERNEL_ELF)

# include tools/raspi4/common/docker.mk
DOCKER_IMAGE := rustembedded/osdev-utils:2021.12
# include tools/raspi4/common/format.mk
define disk_usage_KiB
    @printf '%s KiB\n' `du $(DU_ARGUMENTS) $(1) | cut -f1`
endef

define color_header
    @tput setaf 6 2> /dev/null || true
    @printf '\n%s\n' $(1)
    @tput sgr0 2> /dev/null || true
endef

define color_progress_prefix
    @tput setaf 2 2> /dev/null || true
    @tput bold 2 2> /dev/null || true
    @printf '%12s ' $(1)
    @tput sgr0 2> /dev/null || true
endef
# include tools/raspi4/common/operating_system.mk
ifeq ($(shell uname -s),Linux)
    DU_ARGUMENTS = --block-size=1024 --apparent-size
else ifeq ($(shell uname -s),Darwin)
    DU_ARGUMENTS = -k -A
endif


