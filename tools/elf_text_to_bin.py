#!/usr/bin/env python3
"""Extract the .text section from a little-endian ELF32 object file."""

from pathlib import Path
import struct
import sys


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} INPUT.o OUTPUT.bin")

    source = Path(sys.argv[1]).read_bytes()
    if source[:4] != b"\x7fELF" or source[4:6] != b"\x01\x01":
        raise SystemExit("input must be a little-endian ELF32 object")

    section_offset = struct.unpack_from("<I", source, 32)[0]
    section_entry_size = struct.unpack_from("<H", source, 46)[0]
    section_count = struct.unpack_from("<H", source, 48)[0]
    names_index = struct.unpack_from("<H", source, 50)[0]

    def section(index: int) -> tuple[int, int, int]:
        offset = section_offset + index * section_entry_size
        name, _, _, _, file_offset, size = struct.unpack_from("<IIIIII", source, offset)
        return name, file_offset, size

    _, names_offset, names_size = section(names_index)
    names = source[names_offset : names_offset + names_size]

    for index in range(section_count):
        name_offset, file_offset, size = section(index)
        end = names.find(b"\0", name_offset)
        name = names[name_offset:end]
        if name == b".text":
            output = source[file_offset : file_offset + size]
            if len(output) != 512 or output[-2:] != b"\x55\xaa":
                raise SystemExit(".text is not a valid 512-byte BIOS boot sector")
            Path(sys.argv[2]).write_bytes(output)
            return

    raise SystemExit(".text section not found")


if __name__ == "__main__":
    main()
