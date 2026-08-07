#!/usr/bin/env python3
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
dockerfile = (ROOT / "scripts/docker/arm64/Dockerfile").read_text()
devcontainer = json.loads((ROOT / ".devcontainer/devcontainer.json").read_text())

for package in ("gdb-multiarch", "clangd-16"):
    assert package in dockerfile, f"Dockerfile missing {package}"
assert "ln -s /usr/bin/clangd-16 /usr/local/bin/clangd" in dockerfile

run_args = devcontainer["runArgs"]
assert "--cap-add=SYS_PTRACE" in run_args
assert "--security-opt=seccomp=unconfined" in run_args

vscode = devcontainer["customizations"]["vscode"]
expected_extensions = {
    "ms-vscode.cpptools",
    "ms-vscode.hexeditor",
    "llvm-vs-code-extensions.vscode-clangd",
    "ms-vscode.makefile-tools",
    "twxs.cmake",
    "dan-c-underwood.arm",
}
assert expected_extensions <= set(vscode["extensions"])
assert vscode["settings"]["terminal.integrated.defaultProfile.linux"] == "bash"

print("Dev Container configuration tests passed")
