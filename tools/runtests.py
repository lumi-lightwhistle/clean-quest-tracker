"""Runs the offline regression tests (tests/run.lua) with whatever Lua 5.1 this machine has.

Usage: python tools/runtests.py

Tries, in order: a `lua5.1`, `lua51` or `luajit` program, a `lua` program that is version 5.1, then the `lupa` Python
package (pip install lupa, version 2 or later), which carries its own Lua 5.1. Exit code: 0 all passed, 1 a check
failed, 77 no Lua found. tools/prereview.py calls this and treats 77 as a skip, not a failure (not 2, which Python
itself uses when it can't run a script).
"""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NO_LUA = 77


def find_program():
    for name in ("lua5.1", "lua51", "luajit"):
        path = shutil.which(name)
        if path:
            return path
    path = shutil.which("lua")
    if path:
        out = subprocess.run([path, "-v"], capture_output=True, text=True)
        if "5.1" in out.stdout + out.stderr:
            return path
    return None


def run_program(path):
    return subprocess.run([path, "tests/run.lua"], cwd=ROOT).returncode


def run_lupa():
    try:
        from lupa import lua51
    except ImportError:
        return None
    lua = lua51.LuaRuntime()
    lua.globals().CQT_ROOT = ROOT.as_posix()
    lua.execute((ROOT / "tests" / "run.lua").read_text(encoding="utf-8"))
    sys.stdout.flush()
    result = lua.globals().CQT_RESULT
    return 0 if result and result.fail == 0 else 1


def main():
    program = find_program()
    if program:
        return run_program(program)
    code = run_lupa()
    if code is None:
        print('No Lua 5.1 found: install one (see docs/testing.md) or run `pip install "lupa>=2"`.')
        return NO_LUA
    return code


if __name__ == "__main__":
    sys.exit(main())
