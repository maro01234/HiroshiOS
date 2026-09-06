.section .text
.code64
.global efi_main

# UEFI x64 applications use the Microsoft x64 calling convention:
#   RCX = image handle, RDX = EFI_SYSTEM_TABLE pointer
efi_main:
    # Reserve the required 32-byte shadow space plus local storage.  RSP is
    # 16-byte aligned at each call below.
    subq $72, %rsp

    # EFI_SYSTEM_TABLE.ConOut is at offset 64 on x86-64.
    movq 64(%rdx), %rax
    movq %rax, 32(%rsp)

    # EFI_SYSTEM_TABLE.ConIn is at offset 48 on x86-64.
    movq 48(%rdx), %rax
    movq %rax, 40(%rsp)

    # ConOut->ClearScreen(ConOut)
    movq 32(%rsp), %rcx
    callq *48(%rcx)

    # ConOut->OutputString(ConOut, message)
    movq 32(%rsp), %rcx
    leaq message(%rip), %rdx
    callq *8(%rcx)

#ifdef QEMU_TEST
    # Mirror the ASCII portion to QEMU's debug port in test builds only.
    leaq message(%rip), %r8
    movw $0x00e9, %dx
debug_loop:
    movzwl (%r8), %eax
    testw %ax, %ax
    jz debug_finished
    outb %al, %dx
    addq $2, %r8
    jmp debug_loop

debug_finished:
    # Exit QEMU through its optional test device.
    movw $0x00f4, %dx
    movb $0x10, %al
    outb %al, %dx
#endif

wait_for_key:
    # ConIn->ReadKeyStroke(ConIn, &key). EFI_NOT_READY means try again.
    movq 40(%rsp), %rcx
    leaq 48(%rsp), %rdx
    callq *8(%rcx)
    testq %rax, %rax
    jnz wait_for_key

    # EFI_SUCCESS: return control to GRUB or the firmware boot manager.
    xorq %rax, %rax
    addq $72, %rsp
    retq

.balign 2
message:
    .incbin "build/uefi-message.bin"
