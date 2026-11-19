"""Mechanical checks to run before a commit (the first step of the pre-commit-review skill).

Usage: python tools/prereview.py          checks the files changed since HEAD (staged, unstaged and new); when nothing is
                                          changed (the work is already committed) it checks every Lua file
       python tools/prereview.py --all    checks every Lua file

What it checks, and why a person or a reviewer agent still has to read the rest:
  1. Syntax        tools/luacheck.py on each Lua file.
  2. Load order    every Lua file is listed in the .toc and every .toc entry exists (CI does the same).
  3. Dead settings keys in Q.defaults (Core/Core.lua) that no other line of Lua reads.
  4. Highlight keys `hl = "x"` in the settings pages that nothing handles (a hover would shade nothing).
  5. Stale words   page names or phrases that older versions used, left in Lua comments or text.
The unread-settings check is a heuristic: a key named only in a comment counts as read. It cannot judge design,
duplication or whether a comment is still true; that is the reviewer's job.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STALE = {
    "Text & bars": "that page no longer exists (its settings are on Quests and Layout)",
    "POI_ROOM ": "replaced by T.PoiRoom()",
    "bandRim": "the bar's teal rim was removed",
    "box.rim": "the search box's own rim was removed",
}
# Settings read only through a loop over the defaults, or stored for the add-on's own bookkeeping.
INTERNAL_KEYS = {"point", "x", "y", "schema", "legacyPosition"}
# Settings whose hover has nothing in the tracker to shade (they change behaviour, not a visible part), on purpose.
NO_SHADE_KEYS = {"anim", "hide"}


def run(*args):
    return subprocess.run(args, cwd=ROOT, capture_output=True, text=True).stdout


def all_files():
    """Every Lua file git knows about (tracked, or new and not ignored): never build output or copies."""
    names = set(run("git", "ls-files", "*.lua").splitlines())
    names |= set(run("git", "ls-files", "--others", "--exclude-standard", "*.lua").splitlines())
    return sorted(n for n in names if (ROOT / n).exists())


def lua_files(everything):
    if everything:
        return all_files()
    names = set(run("git", "diff", "--name-only", "HEAD").splitlines())
    names |= set(run("git", "ls-files", "--others", "--exclude-standard").splitlines())
    changed = sorted(n for n in names if n.endswith(".lua") and (ROOT / n).exists())
    return changed or all_files()


def check_syntax(files):
    bad = []
    for name in files:
        out = subprocess.run([sys.executable, "tools/luacheck.py", name], cwd=ROOT, capture_output=True, text=True)
        text = (out.stdout + out.stderr).strip()
        if out.returncode != 0 or not text.endswith("OK"):
            bad.append(f"{name}: {text.splitlines()[-1] if text else 'no output'}")
    return bad


def check_toc():
    toc = (ROOT / "CleanQuestTracker.toc").read_text(encoding="utf-8").splitlines()
    listed = {line.strip().replace("\\", "/") for line in toc if line.strip().endswith(".lua")}
    # Same rule as CI: every Lua file outside tools/ belongs in the .toc.
    on_disk = {n for n in all_files() if not n.startswith("tools/")}
    problems = [f"not in the .toc: {n}" for n in sorted(on_disk - listed)]
    problems += [f".toc lists a missing file: {n}" for n in sorted(listed - on_disk)]
    return problems


def all_lua_text():
    return {n: (ROOT / n).read_text(encoding="utf-8", errors="replace") for n in all_files()}


def check_dead_settings(texts):
    core = texts["Core/Core.lua"]
    block = re.search(r"Q\.defaults = \{(.*?)\n\}", core, re.S)
    keys = re.findall(r"^\t([A-Za-z_][A-Za-z0-9_]*) = ", block.group(1), re.M) if block else []
    problems = []
    for key in keys:
        if key in INTERNAL_KEYS:
            continue
        pattern = re.compile(r"\b" + re.escape(key) + r"\b")
        uses = sum(len(pattern.findall(text)) for name, text in texts.items())
        defined_only = len(pattern.findall(block.group(1)))
        if uses - defined_only <= 0:
            problems.append(f"setting '{key}' is in Q.defaults but nothing reads it")
    return problems


def check_highlight_keys(texts):
    pages = texts["UI/OptionsPages.lua"]
    wanted = set(re.findall(r'hl = "(\w+)"', pages)) | set(re.findall(r'SetHighlight\("(\w+)"\)', texts["UI/Options.lua"]))
    handled = set(re.findall(r"SHADERS\.(\w+)\s*=|function SHADERS\.(\w+)\(", texts["Tracker/TrackerHighlight.lua"]))
    handled = {a or b for a, b in handled}
    frame = texts["UI/Frame.lua"]
    problems = []
    for key in sorted(wanted - handled - NO_SHADE_KEYS):
        if f'"{key}"' not in frame:
            problems.append(f"highlight key '{key}' is used by a setting but no shader or frame handler names it")
    return problems


def check_stale(texts):
    problems = []
    for name, text in texts.items():
        for number, line in enumerate(text.splitlines(), 1):
            for phrase, why in STALE.items():
                if phrase in line:
                    problems.append(f"{name}:{number}: '{phrase.strip()}' ({why})")
    return problems


def main():
    everything = "--all" in sys.argv
    files = lua_files(everything)
    texts = all_lua_text()
    sections = [
        ("Syntax", check_syntax(files)),
        ("Load order (.toc)", check_toc()),
        ("Settings nothing reads", check_dead_settings(texts)),
        ("Highlight keys", check_highlight_keys(texts)),
        ("Stale wording", check_stale(texts)),
    ]
    print(f"Checked {len(files)} Lua file(s): {', '.join(files) or 'none changed'}\n")
    failed = 0
    for title, problems in sections:
        print(f"[{'ok' if not problems else 'FIX'}] {title}")
        for problem in problems:
            print(f"    - {problem}")
        failed += len(problems)
    print(f"\n{failed} problem(s)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
