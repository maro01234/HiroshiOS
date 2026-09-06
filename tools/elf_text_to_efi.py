#!/usr/bin/env python3
"""Wrap relocation-free ELF64 .text as a minimal x64 UEFI PE32+ image."""

from pathlib import Path
import struct
import sys


FILE_ALIGNMENT = 0x200
SECTION_ALIGNMENT = 0x1000
TEXT_RVA = 0x1000
RELOC_RVA = 0x2000
PE_OFFSET = 0x80
HEADERS_SIZE = 0x200


def align(value: int, alignment: int) -> int:
    return (value + alignment - 1) & ~(alignment - 1)


def extract_text(source: bytes) -> bytes:
    if source[:6] != b"\x7fELF\x02\x01":
        raise SystemExit("input must be a little-endian ELF64 object")

    section_offset = struct.unpack_from("<Q", source, 40)[0]
    section_entry_size = struct.unpack_from("<H", source, 58)[0]
    section_count = struct.unpack_from("<H", source, 60)[0]
    names_index = struct.unpack_from("<H", source, 62)[0]

    def section(index: int) -> tuple[int, int, int, int, int]:
        offset = section_offset + index * section_entry_size
        name, kind, _, _, file_offset, size, _, info, _, _ = struct.unpack_from(
            "<IIQQQQIIQQ", source, offset
        )
        return name, kind, file_offset, size, info

    _, _, names_offset, names_size, _ = section(names_index)
    names = source[names_offset : names_offset + names_size]
    text_index = -1
    text = b""

    for index in range(section_count):
        name_offset, _, file_offset, size, _ = section(index)
        end = names.find(b"\0", name_offset)
        if names[name_offset:end] == b".text":
            text_index = index
            text = source[file_offset : file_offset + size]
            break

    if text_index < 0:
        raise SystemExit(".text section not found")

    for index in range(section_count):
        _, kind, _, size, target_index = section(index)
        if kind in (4, 9) and size and target_index == text_index:
            raise SystemExit(".text contains unresolved relocations")

    if not text or len(text) > SECTION_ALIGNMENT:
        raise SystemExit(".text must fit in one non-empty PE section")
    return text


def optional_header(text_raw_size: int, reloc_size: int) -> bytes:
    header = bytearray()
    header += struct.pack("<HBB", 0x20B, 1, 0)  # PE32+, linker version
    header += struct.pack("<III", text_raw_size, FILE_ALIGNMENT, 0)
    header += struct.pack("<II", TEXT_RVA, TEXT_RVA)
    header += struct.pack("<Q", 0x400000)  # Preferred image base
    header += struct.pack("<II", SECTION_ALIGNMENT, FILE_ALIGNMENT)
    header += struct.pack("<HHHHHH", 0, 0, 0, 0, 2, 0)
    header += struct.pack("<I", 0)
    header += struct.pack("<III", 0x3000, HEADERS_SIZE, 0)
    header += struct.pack("<HH", 10, 0)  # EFI application subsystem
    header += struct.pack("<QQQQ", 0x100000, 0x1000, 0x100000, 0x1000)
    header += struct.pack("<II", 0, 16)

    directories = [(0, 0)] * 16
    directories[5] = (RELOC_RVA, reloc_size)
    for rva, size in directories:
        header += struct.pack("<II", rva, size)

    if len(header) != 0xF0:
        raise AssertionError(f"unexpected optional header size: {len(header)}")
    return bytes(header)


def section_header(
    name: bytes, virtual_size: int, rva: int, raw_size: int, raw_offset: int, flags: int
) -> bytes:
    return struct.pack(
        "<8sIIIIIIHHI",
        name.ljust(8, b"\0"),
        virtual_size,
        rva,
        raw_size,
        raw_offset,
        0,
        0,
        0,
        0,
        flags,
    )


def make_efi(text: bytes) -> bytes:
    text_raw_size = align(len(text), FILE_ALIGNMENT)
    reloc = struct.pack("<IIHH", TEXT_RVA, 12, 0, 0)
    reloc_raw_size = FILE_ALIGNMENT

    dos = bytearray(PE_OFFSET)
    dos[:2] = b"MZ"
    struct.pack_into("<I", dos, 0x3C, PE_OFFSET)

    pe = bytearray(dos)
    pe += b"PE\0\0"
    pe += struct.pack(
        "<HHIIIHH",
        0x8664,
        2,
        0,
        0,
        0,
        0xF0,
        0x0022,
    )
    pe += optional_header(text_raw_size, len(reloc))
    pe += section_header(
        b".text", len(text), TEXT_RVA, text_raw_size, HEADERS_SIZE, 0x60000020
    )
    pe += section_header(
        b".reloc",
        len(reloc),
        RELOC_RVA,
        reloc_raw_size,
        HEADERS_SIZE + text_raw_size,
        0x42000040,
    )

    if len(pe) > HEADERS_SIZE:
        raise SystemExit("PE headers exceed file alignment")
    pe += bytes(HEADERS_SIZE - len(pe))
    pe += text + bytes(text_raw_size - len(text))
    pe += reloc + bytes(reloc_raw_size - len(reloc))
    return bytes(pe)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} INPUT.o OUTPUT.efi")

    text = extract_text(Path(sys.argv[1]).read_bytes())
    Path(sys.argv[2]).write_bytes(make_efi(text))


if __name__ == "__main__":
    main()
