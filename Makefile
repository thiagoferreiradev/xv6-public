#--------------------------------------------------------------------------------
# Directory Structure
#--------------------------------------------------------------------------------

# Main build directory
BUILD_DIR       := build

# Source code directories
KSRC_DIR        := kernel
KINCLUDE_DIR    := include
TOOLSRC_DIR     := tools
UINCLUDE_DIR    := user/include
ULIB_DIR        := user/lib
UAPPS_DIR       := user/apps
USRC_DIR        := user/src

# Build subdirectories
KOBJ_DIR        := $(BUILD_DIR)/kernel
UOBJ_DIR        := $(BUILD_DIR)/user
FS_STAGE_DIR    := $(BUILD_DIR)/fs_stage

# Create necessary build directories at the beginning
$(shell mkdir -p $(KOBJ_DIR) $(UOBJ_DIR) $(FS_STAGE_DIR))

#--------------------------------------------------------------------------------
# Toolchain and Compilation Flags
#--------------------------------------------------------------------------------

# Try to infer the correct TOOLPREFIX if not set
ifndef TOOLPREFIX
TOOLPREFIX := $(shell if i386-jos-elf-objdump -i 2>&1 | grep '^elf32-i386$$' >/dev/null 2>&1; \
	then echo 'i386-jos-elf-'; \
	elif objdump -i 2>&1 | grep 'elf32-i386' >/dev/null 2>&1; \
	then echo ''; \
	else echo "***" 1>&2; \
	echo "*** Error: Couldn't find an i386-*-elf version of GCC/binutils." 1>&2; \
	echo "*** Is the directory with i386-jos-elf-gcc in your PATH?" 1>&2; \
	echo "*** If your i386-*-elf toolchain is installed with a command" 1>&2; \
	echo "*** prefix other than 'i386-jos-elf-', set your TOOLPREFIX" 1>&2; \
	echo "*** environment variable to that prefix and run 'make' again." 1>&2; \
	echo "*** To turn off this error, run 'gmake TOOLPREFIX= ...'." 1>&2; \
	echo "***" 1>&2; exit 1; fi)
endif

CC = $(TOOLPREFIX)gcc
AS = $(TOOLPREFIX)gas
LD = $(TOOLPREFIX)ld
OBJCOPY = $(TOOLPREFIX)objcopy
OBJDUMP = $(TOOLPREFIX)objdump

CFLAGS = -fno-pic -static -fno-builtin -fno-strict-aliasing -O2 -Wall -MD -ggdb -m32 -Werror -fno-omit-frame-pointer
CFLAGS += -I. -I$(KINCLUDE_DIR) -I$(UINCLUDE_DIR)
CFLAGS += $(shell $(CC) -fno-stack-protector -E -x c /dev/null >/dev/null 2>&1 && echo -fno-stack-protector)
ASFLAGS = -m32 -gdwarf-2 -Wa,-divide
LDFLAGS += -m $(shell $(LD) -V | grep elf_i386 2>/dev/null | head -n 1)

# Disable PIE when possible
ifneq ($(shell $(CC) -dumpspecs 2>/dev/null | grep -e '[^f]no-pie'),)
CFLAGS += -fno-pie -no-pie
endif
ifneq ($(shell $(CC) -dumpspecs 2>/dev/null | grep -e '[^f]nopie'),)
CFLAGS += -fno-pie -nopie
endif

#--------------------------------------------------------------------------------
# Kernel Compilation
#--------------------------------------------------------------------------------

KOBJS = \
    $(KOBJ_DIR)/bio.o \
    $(KOBJ_DIR)/console.o \
    $(KOBJ_DIR)/exec.o \
    $(KOBJ_DIR)/file.o \
    $(KOBJ_DIR)/fs.o \
    $(KOBJ_DIR)/ide.o \
    $(KOBJ_DIR)/ioapic.o \
    $(KOBJ_DIR)/kalloc.o \
    $(KOBJ_DIR)/kbd.o \
    $(KOBJ_DIR)/lapic.o \
    $(KOBJ_DIR)/log.o \
    $(KOBJ_DIR)/main.o \
    $(KOBJ_DIR)/mp.o \
    $(KOBJ_DIR)/picirq.o \
    $(KOBJ_DIR)/pipe.o \
    $(KOBJ_DIR)/proc.o \
    $(KOBJ_DIR)/sleeplock.o \
    $(KOBJ_DIR)/spinlock.o \
    $(KOBJ_DIR)/string.o \
    $(KOBJ_DIR)/swtch.o \
    $(KOBJ_DIR)/syscall.o \
    $(KOBJ_DIR)/sysfile.o \
    $(KOBJ_DIR)/sysproc.o \
    $(KOBJ_DIR)/trap.o \
    $(KOBJ_DIR)/trapasm.o \
    $(KOBJ_DIR)/uart.o \
    $(KOBJ_DIR)/vectors.o \
    $(KOBJ_DIR)/vm.o

MEMFSOBJS = $(filter-out $(KOBJ_DIR)/ide.o, $(KOBJS)) $(KOBJ_DIR)/memide.o

$(KSRC_DIR)/vectors.S: $(TOOLSRC_DIR)/vectors.pl
	@echo "Generating vectors.S..."
	perl $(TOOLSRC_DIR)/vectors.pl > $(KSRC_DIR)/vectors.S

$(BUILD_DIR)/bootblock: $(KOBJ_DIR)/bootasm.o $(KOBJ_DIR)/bootmain.o
	@echo "Linking (LD) bootblock..."
	$(LD) $(LDFLAGS) -N -e start -Ttext 0x7C00 -o $(BUILD_DIR)/bootblock.o $^
	$(OBJCOPY) -S -O binary -j .text $(BUILD_DIR)/bootblock.o $(BUILD_DIR)/bootblock
	perl $(TOOLSRC_DIR)/sign.pl $(BUILD_DIR)/bootblock

$(BUILD_DIR)/entryother: $(KOBJ_DIR)/entryother.o
	@echo "Linking (LD) entryother..."
	$(LD) $(LDFLAGS) -N -e start -Ttext 0x7000 -o $(BUILD_DIR)/entryother.o $<
	$(OBJCOPY) -S -O binary -j .text $(BUILD_DIR)/entryother.o $(BUILD_DIR)/entryother

$(BUILD_DIR)/initcode: $(KOBJ_DIR)/initcode.o
	@echo "Linking (LD) initcode..."
	$(LD) $(LDFLAGS) -N -e start -Ttext 0 -o $(BUILD_DIR)/initcode.out $<
	$(OBJCOPY) -S -O binary $(BUILD_DIR)/initcode.out $(BUILD_DIR)/initcode

$(BUILD_DIR)/kernel.elf: $(KOBJ_DIR)/entry.o $(KOBJS) $(BUILD_DIR)/initcode $(BUILD_DIR)/entryother $(KSRC_DIR)/kernel.ld
	@echo "Linking (LD) the Kernel..."
	cp $(BUILD_DIR)/initcode .
	cp $(BUILD_DIR)/entryother .
	$(LD) $(LDFLAGS) -T $(KSRC_DIR)/kernel.ld -o $@ \
	    $(KOBJ_DIR)/entry.o $(KOBJS) \
	    -b binary initcode -b binary entryother
	rm initcode entryother
	@echo "Creating kernel assembly and symbol files..."
	$(OBJDUMP) -S $@ > $(BUILD_DIR)/kernel.asm
	$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $(BUILD_DIR)/kernel.sym

$(BUILD_DIR)/kernelmemfs.elf: $(KOBJ_DIR)/entry.o $(MEMFSOBJS) $(BUILD_DIR)/initcode $(BUILD_DIR)/entryother $(KSRC_DIR)/kernel.ld fs.img
	@echo "Linking (LD) the MemFS Kernel..."
	cp $(BUILD_DIR)/initcode .
	cp $(BUILD_DIR)/entryother .
	$(LD) $(LDFLAGS) -T $(KSRC_DIR)/kernel.ld -o $@ \
	    $(KOBJ_DIR)/entry.o $(MEMFSOBJS) \
	    -b binary initcode -b binary entryother -b binary fs.img
	rm initcode entryother
	@echo "Creating memfs kernel assembly and symbol files..."
	$(OBJDUMP) -S $@ > $(BUILD_DIR)/kernelmemfs.asm
	$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $(BUILD_DIR)/kernelmemfs.sym

$(KOBJ_DIR)/%.o: $(KSRC_DIR)/%.c
	$(CC) $(CFLAGS) -c -o $@ $<
$(KOBJ_DIR)/%.o: $(KSRC_DIR)/%.S
	$(CC) $(CFLAGS) -c -o $@ $<

#--------------------------------------------------------------------------------
# Filesystem Compilation (User Programs)
#--------------------------------------------------------------------------------

vpath %.c $(UAPPS_DIR):$(ULIB_DIR):$(USRC_DIR)
vpath %.S $(ULIB_DIR)

ULIB_SRCS   = $(notdir $(wildcard $(ULIB_DIR)/*.c) $(wildcard $(ULIB_DIR)/*.S))
UAPPS_SRCS  = $(notdir $(wildcard $(UAPPS_DIR)/*.c))
USRC_FILES  = $(notdir $(wildcard $(USRC_DIR)/*.c))

ULIB_OBJS   = $(addprefix $(UOBJ_DIR)/, $(ULIB_SRCS:.c=.o))
UAPPS_OBJS  = $(addprefix $(UOBJ_DIR)/, $(UAPPS_SRCS:.c=.o))
USRC_OBJS   = $(addprefix $(UOBJ_DIR)/, $(USRC_FILES:.c=.o))
ULIB_OBJS   := $(ULIB_OBJS:.S=.o)

UPROGS_EXEC_PATH = $(addprefix $(FS_STAGE_DIR)/, $(UAPPS_SRCS:.c=))

$(UPROGS_EXEC_PATH): $(FS_STAGE_DIR)/%: $(UOBJ_DIR)/%.o $(ULIB_OBJS) $(USRC_OBJS)
	@echo "Linking (LD) user program $@"
	$(LD) $(LDFLAGS) -N -e main -Ttext 0 -o $@ $^

$(UOBJ_DIR)/%.o: %.c
	@echo "Compiling user C source: $<"
	$(CC) $(CFLAGS) -c -o $@ $<

$(UOBJ_DIR)/%.o: %.S
	@echo "Compiling user S source: $<"
	$(CC) $(CFLAGS) -c -o $@ $<

#--------------------------------------------------------------------------------
# Building the Final Images (fs.img, xv6.img)
#--------------------------------------------------------------------------------

$(BUILD_DIR)/mkfs: $(TOOLSRC_DIR)/mkfs.c $(KINCLUDE_DIR)/fs.h
	@echo "Compiling the mkfs tool..."
	gcc -Werror -Wall -iquote include -o $@ $(TOOLSRC_DIR)/mkfs.c

fs.img: $(BUILD_DIR)/mkfs README $(UPROGS_EXEC_PATH)
	@echo "Creating the filesystem image (fs.img)..."
	(cd $(FS_STAGE_DIR) && \
	../../$(BUILD_DIR)/mkfs ../../$@ ../../README $(notdir $(UPROGS_EXEC_PATH)))

xv6.img: $(BUILD_DIR)/bootblock $(BUILD_DIR)/kernel.elf fs.img
	@echo "Assembling the final disk image (xv6.img)..."
	dd if=/dev/zero of=$@ count=10000
	dd if=$(BUILD_DIR)/bootblock of=$@ conv=notrunc
	dd if=$(BUILD_DIR)/kernel.elf of=$@ seek=1 conv=notrunc

xv6memfs.img: $(BUILD_DIR)/bootblock $(BUILD_DIR)/kernelmemfs.elf
	@echo "Assembling the final memfs disk image (xv6memfs.img)..."
	dd if=/dev/zero of=$@ count=10000
	dd if=$(BUILD_DIR)/bootblock of=$@ conv=notrunc
	dd if=$(BUILD_DIR)/kernelmemfs.elf of=$@ seek=1 conv=notrunc

#--------------------------------------------------------------------------------
# QEMU
#--------------------------------------------------------------------------------

# Try to infer the correct QEMU
ifndef QEMU
QEMU = $(shell if which qemu > /dev/null; \
	then echo qemu; exit; \
	elif which qemu-system-i386 > /dev/null; \
	then echo qemu-system-i386; exit; \
	elif which qemu-system-x86_64 > /dev/null; \
	then echo qemu-system-x86_64; exit; \
	else \
	qemu=/Applications/Q.app/Contents/MacOS/i386-softmmu.app/Contents/MacOS/i386-softmmu; \
	if test -x $$qemu; then echo $$qemu; exit; fi; fi; \
	echo "***" 1>&2; \
	echo "*** Error: Couldn't find a working QEMU executable." 1>&2; \
	echo "*** Is the directory containing the qemu binary in your PATH" 1>&2; \
	echo "*** or have you tried setting the QEMU variable in Makefile?" 1>&2; \
	echo "***" 1>&2; exit 1)
endif

CPUS ?= 2
QEMUOPTS = -drive file=fs.img,index=1,media=disk,format=raw -drive file=xv6.img,index=0,media=disk,format=raw -smp $(CPUS) -m 512 $(QEMUEXTRA)

qemu: fs.img xv6.img
	$(QEMU) -serial mon:stdio $(QEMUOPTS)

qemu-memfs: xv6memfs.img
	$(QEMU) -drive file=xv6memfs.img,index=0,media=disk,format=raw -smp $(CPUS) -m 256

qemu-nox: fs.img xv6.img
	$(QEMU) -nographic $(QEMUOPTS)

qemu-nox-memfs: xv6memfs.img
	$(QEMU) -nographic -drive file=xv6memfs.img,index=0,media=disk,format=raw -smp $(CPUS) -m 256

#--------------------------------------------------------------------------------
# Main and Cleanup Targets
#--------------------------------------------------------------------------------

all: xv6.img xv6memfs.img

clean:
	@echo "Cleaning build files..."
	rm -rf $(BUILD_DIR) fs.img xv6.img xv6memfs.img $(KSRC_DIR)/vectors.S

.PHONY: all clean

-include $(wildcard $(KOBJ_DIR)/*.d) $(wildcard $(UOBJ_DIR)/*.d)