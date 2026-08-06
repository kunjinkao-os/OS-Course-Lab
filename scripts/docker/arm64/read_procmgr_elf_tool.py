#!/usr/bin/env python3
"""Generate the metadata prefix expected before the ChCore procmgr ELF."""

import struct
import sys
from typing import NoReturn

from elftools.common.exceptions import ELFError
from elftools.elf.enums import ENUM_P_TYPE_BASE
from elftools.elf.elffile import ELFFile


def fail(message: str) -> NoReturn:
    print(f"read_procmgr_elf_tool: {message}", file=sys.stderr)
    raise SystemExit(1)


def numeric_program_type(value) -> int:
    if isinstance(value, int):
        return value
    mapped_value = ENUM_P_TYPE_BASE.get(value)
    if isinstance(mapped_value, int):
        return mapped_value
    for number, name in ENUM_P_TYPE_BASE.items():
        if isinstance(number, int) and name == value:
            return number
    fail(f"unsupported program header type: {value}")


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: read_procmgr_elf_tool <procmgr.elf>")

    try:
        with open(sys.argv[1], "rb") as stream:
            elf = ELFFile(stream)
            headers = list(elf.iter_segments())
            if elf.elfclass != 64 or not elf.little_endian:
                fail("procmgr must be a little-endian ELF64 file")
            if len(headers) != 3:
                fail(f"expected 3 program headers, found {len(headers)}")

            memory_size = sum(
                segment["p_memsz"]
                for segment in headers
                if segment["p_type"] == "PT_LOAD"
            )
            metadata = struct.pack(
                ">6Q",
                memory_size,
                elf.header["e_entry"],
                elf.header["e_flags"],
                elf.header["e_phentsize"],
                elf.header["e_phnum"],
                headers[0]["p_vaddr"] + elf.header["e_phoff"],
            )
            program_headers = b"".join(
                struct.pack(
                    "<II6Q",
                    numeric_program_type(segment["p_type"]),
                    segment["p_flags"],
                    segment["p_offset"],
                    segment["p_vaddr"],
                    segment["p_paddr"],
                    segment["p_filesz"],
                    segment["p_memsz"],
                    segment["p_align"],
                )
                for segment in headers
            )
    except (ELFError, OSError, KeyError, struct.error, ValueError) as error:
        fail(str(error))

    with open("elf_info.temp", "wb") as output:
        output.write(metadata)
        output.write(program_headers)


if __name__ == "__main__":
    main()
