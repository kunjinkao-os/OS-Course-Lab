#!/usr/bin/env python3
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def load(name):
    return json.loads((ROOT / ".vscode" / name).read_text())


settings = load("settings.json")
tasks = load("tasks.json")["tasks"]
launches = load("launch.json")["configurations"]

assert settings["clangd.arguments"] == ["--compile-commands-dir=build/kernel"]
assert settings["debug.allowBreakpointsEverywhere"] is True
assert settings["cmake.configureOnOpen"] is False
assert settings["cmake.buildDirectory"] == "${workspaceFolder}/build/cmake-tools"

tasks_by_label = {task["label"]: task for task in tasks}
assert tasks_by_label["Build ChCore"]["command"] == "make"
assert tasks_by_label["Setup QEMU"]["command"] == "make qemu-gdb"
assert tasks_by_label["Setup QEMU"]["isBackground"] is True
background = tasks_by_label["Setup QEMU"]["problemMatcher"]["background"]
assert background["endsPattern"] == r"^\[QEMU\] Waiting for GDB Connection$"
assert tasks_by_label["Stop QEMU"]["command"] == "make qemu-gdb-stop"
for task in tasks:
    assert task["options"]["cwd"] == "${workspaceFolder}"

assert len(launches) == 1
launch = launches[0]
assert launch["name"] == "QEMU (cppdbg)"
assert launch["type"] == "cppdbg"
assert launch["program"] == "${workspaceFolder}/build/kernel.img"
assert launch["cwd"] == "${workspaceFolder}"
assert launch["MIMode"] == "gdb"
assert launch["miDebuggerPath"] == "/usr/bin/gdb-multiarch"
assert launch["targetArchitecture"] == "arm64"
assert launch["miDebuggerServerAddress"] == "localhost:1234"
assert launch["preLaunchTask"] == "Setup QEMU"
assert launch["postDebugTask"] == "Stop QEMU"
assert launch["stopAtEntry"] is True

print("VS Code debug configuration tests passed")
