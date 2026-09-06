BUILD_DIR := build
BOOT_OBJECT := $(BUILD_DIR)/boot.o
BOOT_IMAGE := $(BUILD_DIR)/HiroshiOS.img
UEFI_MESSAGE := $(BUILD_DIR)/uefi-message.bin
UEFI_OBJECT := $(BUILD_DIR)/uefi-boot.o
UEFI_APP := $(BUILD_DIR)/HiroshiOS.efi
UEFI_FALLBACK := $(BUILD_DIR)/BOOTX64.EFI
UEFI_ESP := $(BUILD_DIR)/esp
UEFI_FIRMWARE_COPY := $(BUILD_DIR)/edk2-x86_64-code.fd
UEFI_TEST_OBJECT := $(BUILD_DIR)/uefi-test-boot.o
UEFI_TEST_APP := $(BUILD_DIR)/HiroshiOS-test.efi
UEFI_TEST_ESP := $(BUILD_DIR)/test-esp

CLANG ?= clang
PYTHON ?= python3
QEMU ?= qemu-system-i386
QEMU_X64 ?= qemu-system-x86_64
DETECTED_UEFI_FIRMWARE := $(firstword $(wildcard \
	/usr/local/share/qemu/edk2-x86_64-code.fd \
	/opt/homebrew/share/qemu/edk2-x86_64-code.fd \
	/usr/local/Cellar/qemu/*/share/qemu/edk2-x86_64-code.fd \
	/opt/homebrew/Cellar/qemu/*/share/qemu/edk2-x86_64-code.fd))
UEFI_FIRMWARE ?= $(or $(DETECTED_UEFI_FIRMWARE),edk2-x86_64-code.fd)

.PHONY: all bios uefi run run-bios run-uefi test test-bios test-uefi clean

all: bios uefi

bios: $(BOOT_IMAGE)

uefi: $(UEFI_APP) $(UEFI_FALLBACK)

$(BUILD_DIR):
	mkdir -p $@

$(BOOT_OBJECT): boot.S | $(BUILD_DIR)
	$(CLANG) --target=i386-none-elf -c $< -o $@

$(BOOT_IMAGE): $(BOOT_OBJECT) tools/elf_text_to_bin.py
	$(PYTHON) tools/elf_text_to_bin.py $< $@

$(UEFI_MESSAGE): uefi/message.txt tools/text_to_utf16.py | $(BUILD_DIR)
	$(PYTHON) tools/text_to_utf16.py $< $@

$(UEFI_OBJECT): uefi/boot.S $(UEFI_MESSAGE) | $(BUILD_DIR)
	$(CLANG) --target=x86_64-none-elf -c $< -o $@

$(UEFI_TEST_OBJECT): uefi/boot.S $(UEFI_MESSAGE) | $(BUILD_DIR)
	$(CLANG) --target=x86_64-none-elf -DQEMU_TEST=1 -c $< -o $@

$(UEFI_APP): $(UEFI_OBJECT) tools/elf_text_to_efi.py
	$(PYTHON) tools/elf_text_to_efi.py $< $@

$(UEFI_FALLBACK): $(UEFI_APP)
	cp $< $@

$(UEFI_TEST_APP): $(UEFI_TEST_OBJECT) tools/elf_text_to_efi.py
	$(PYTHON) tools/elf_text_to_efi.py $< $@

$(UEFI_ESP)/EFI/BOOT/BOOTX64.EFI: $(UEFI_FALLBACK)
	mkdir -p $(dir $@)
	cp $< $@

$(UEFI_TEST_ESP)/EFI/BOOT/BOOTX64.EFI: $(UEFI_TEST_APP)
	mkdir -p $(dir $@)
	cp $< $@

$(UEFI_FIRMWARE_COPY): | $(BUILD_DIR)
	cp $(UEFI_FIRMWARE) $@

run: run-bios

run-bios: $(BOOT_IMAGE)
	$(QEMU) -drive format=raw,file=$(BOOT_IMAGE) -boot c

run-uefi: $(UEFI_ESP)/EFI/BOOT/BOOTX64.EFI $(UEFI_FIRMWARE_COPY)
	$(QEMU_X64) \
		-machine q35 \
		-m 128M \
		-drive if=pflash,format=raw,file=$(UEFI_FIRMWARE_COPY) \
		-drive format=raw,file=fat:rw:$(UEFI_ESP)

test: test-bios test-uefi

test-bios: $(BOOT_IMAGE)
	@$(QEMU) \
		-drive format=raw,file=$(BOOT_IMAGE) \
		-boot c \
		-display none \
		-monitor none \
		-serial stdio \
		-no-reboot \
		-device isa-debug-exit,iobase=0xf4,iosize=0x04 \
		2>&1 | awk 'index($$0, "Hello World from HiroshiOS!") { hello=1 } index($$0, "+-----+-----+     >>>") { logo=1 } END { exit !(hello && logo) }'
	@echo "PASS: BIOS HiroshiOS printed Hello World and the Windows ASCII art"

test-uefi: $(UEFI_FALLBACK) $(UEFI_TEST_ESP)/EFI/BOOT/BOOTX64.EFI $(UEFI_FIRMWARE_COPY)
	@$(QEMU_X64) \
		-machine q35 \
		-m 128M \
		-drive if=pflash,format=raw,file=$(UEFI_FIRMWARE_COPY) \
		-drive format=raw,file=fat:rw:$(UEFI_TEST_ESP) \
		-display none \
		-monitor none \
		-serial none \
		-debugcon stdio \
		-global isa-debugcon.iobase=0xe9 \
		-no-reboot \
		-device isa-debug-exit,iobase=0xf4,iosize=0x04 \
		2>&1 | awk 'index($$0, "Hello World from HiroshiOS!") { hello=1 } index($$0, "UEFI boot succeeded.") { uefi=1 } END { exit !(hello && uefi) }'
	@echo "PASS: UEFI HiroshiOS booted and printed its message"

clean:
	rm -rf $(BUILD_DIR)
