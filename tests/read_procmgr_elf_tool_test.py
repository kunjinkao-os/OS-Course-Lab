"""Regression tests for read_procmgr_elf_tool enum compatibility."""

import contextlib
import importlib.util
import io
import pathlib
import sys
import types
import unittest
from unittest.mock import patch


HELPER_PATH = (
    pathlib.Path(__file__).resolve().parents[1]
    / "scripts/docker/arm64/read_procmgr_elf_tool.py"
)


def load_helper(enum_mapping):
    """Load the helper with a minimal pyelftools stub and chosen enum mapping."""
    elftools = types.ModuleType("elftools")
    common = types.ModuleType("elftools.common")
    exceptions = types.ModuleType("elftools.common.exceptions")
    elf = types.ModuleType("elftools.elf")
    enums = types.ModuleType("elftools.elf.enums")
    elffile = types.ModuleType("elftools.elf.elffile")

    exceptions.ELFError = type("ELFError", (Exception,), {})
    enums.ENUM_P_TYPE_BASE = enum_mapping
    elffile.ELFFile = object
    elftools.common = common
    common.exceptions = exceptions
    elftools.elf = elf
    elf.enums = enums
    elf.elffile = elffile

    modules = {
        "elftools": elftools,
        "elftools.common": common,
        "elftools.common.exceptions": exceptions,
        "elftools.elf": elf,
        "elftools.elf.enums": enums,
        "elftools.elf.elffile": elffile,
    }
    with patch.dict(sys.modules, modules):
        spec = importlib.util.spec_from_file_location("read_procmgr_elf_tool", HELPER_PATH)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module


class NumericProgramTypeTests(unittest.TestCase):
    def test_accepts_numeric_program_type(self):
        helper = load_helper({})

        self.assertEqual(helper.numeric_program_type(1), 1)

    def test_accepts_name_to_number_enum(self):
        helper = load_helper({"PT_LOAD": 1})

        self.assertEqual(helper.numeric_program_type("PT_LOAD"), 1)

    def test_accepts_number_to_name_enum(self):
        helper = load_helper({1: "PT_LOAD"})

        self.assertEqual(helper.numeric_program_type("PT_LOAD"), 1)

    def test_rejects_unknown_program_type(self):
        helper = load_helper({"PT_LOAD": 1})

        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error:
                helper.numeric_program_type("PT_UNKNOWN")

        self.assertEqual(error.exception.code, 1)


if __name__ == "__main__":
    unittest.main()
