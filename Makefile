BUILD_DIR := build
BOOT_OBJECT := $(BUILD_DIR)/boot.o
BOOT_IMAGE := $(BUILD_DIR)/HiroshiOS.img

CLANG ?= clang
PYTHON ?= python3
QEMU ?= qemu-system-i386

.PHONY: all run test clean

all: $(BOOT_IMAGE)

$(BUILD_DIR):
	mkdir -p $@

$(BOOT_OBJECT): boot.S | $(BUILD_DIR)
	$(CLANG) --target=i386-none-elf -c $< -o $@

$(BOOT_IMAGE): $(BOOT_OBJECT) tools/elf_text_to_bin.py
	$(PYTHON) tools/elf_text_to_bin.py $< $@

run: $(BOOT_IMAGE)
	$(QEMU) -drive format=raw,file=$(BOOT_IMAGE) -boot c

test: $(BOOT_IMAGE)
	@$(QEMU) \
		-drive format=raw,file=$(BOOT_IMAGE) \
		-boot c \
		-display none \
		-monitor none \
		-serial stdio \
		-no-reboot \
		-device isa-debug-exit,iobase=0xf4,iosize=0x04 \
		2>&1 | awk 'index($$0, "Hello World from HiroshiOS!") { hello=1 } index($$0, "+-----+-----+     >>>") { logo=1 } END { exit !(hello && logo) }'
	@echo "PASS: HiroshiOS printed Hello World and the Windows ASCII art"

clean:
	rm -rf $(BUILD_DIR)
