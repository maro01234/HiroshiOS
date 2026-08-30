.section .text
.code16
.global _start

# BIOS loads this 512-byte sector at physical address 0x7c00 and jumps here.
_start:
    cli
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movw $0x7c00, %sp
    sti

    call serial_init

    # Obtain the message address without a linker relocation.  The call pushes
    # the current address, and message-after_call is a compile-time distance.
    call 1f
1:
    popw %si
    addw $(message-1b), %si

print_loop:
    lodsb
    testb %al, %al
    jz finished

    # BIOS teletype service: draw AL in the QEMU display.
    pushw %ax
    movb $0x0e, %ah
    movw $0x0007, %bx
    int $0x10
    popw %ax

    # Also send AL to COM1 so `make test` can inspect the output.
    call serial_write
    jmp print_loop

finished:
    # The optional QEMU test device exits when this port is written.  Without
    # that device (normal `make run`) the write is harmless and execution halts.
    movw $0x00f4, %dx
    movb $0x10, %al
    outb %al, %dx

halt:
    cli
    hlt
    jmp halt

serial_init:
    # Configure COM1 as 38400 baud, 8 data bits, no parity, one stop bit.
    movw $0x03f9, %dx
    movb $0x00, %al
    outb %al, %dx
    movw $0x03fb, %dx
    movb $0x80, %al
    outb %al, %dx
    movw $0x03f8, %dx
    movb $0x03, %al
    outb %al, %dx
    movw $0x03f9, %dx
    movb $0x00, %al
    outb %al, %dx
    movw $0x03fb, %dx
    movb $0x03, %al
    outb %al, %dx
    movw $0x03fa, %dx
    movb $0xc7, %al
    outb %al, %dx
    ret

serial_write:
    pushw %ax
    movw $0x03fd, %dx
2:
    inb %dx, %al
    testb $0x20, %al
    jz 2b
    popw %ax
    movw $0x03f8, %dx
    outb %al, %dx
    ret

message:
    .ascii "Hello World from HiroshiOS!\r\n\r\n"
    # ASCII approximation of the requested 田彡-shaped Windows mark.
    .ascii "   +-----+-----+     >>>\r\n"
    .ascii "   |     |     |      >>>\r\n"
    .ascii "   |     |     |       >>>\r\n"
    .ascii "   +-----+-----+\r\n"
    .ascii "   |     |     |       >>>\r\n"
    .ascii "   |     |     |      >>>\r\n"
    .ascii "   +-----+-----+     >>>\r\n"
    .byte 0

# A legacy BIOS recognizes a boot sector by its exact size and final signature.
.fill 510 - (. - _start), 1, 0
.word 0xaa55
