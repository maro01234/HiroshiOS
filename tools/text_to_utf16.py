#!/usr/bin/env python3
"""Convert a UTF-8 text file to a NUL-terminated UEFI CHAR16 string."""

from pathlib import Path
import sys


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} INPUT.txt OUTPUT.bin")

    text = Path(sys.argv[1]).read_text(encoding="utf-8")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    uefi_text = text.replace("\n", "\r\n")
    Path(sys.argv[2]).write_bytes(uefi_text.encode("utf-16le") + b"\0\0")


if __name__ == "__main__":
    main()
