"""Claude Code hook: stops `git commit` while the mechanical pre-commit checks are failing.

Wired up in .claude/settings.json as a PreToolUse hook on the Bash and PowerShell tools. Claude Code passes the tool call
as JSON on stdin. Anything that is not a `git commit` passes straight through. For a commit it runs tools/prereview.py;
if that reports problems, the commit is blocked (exit code 2) and the report goes back to Claude so it can fix them.

Rules that keep it from getting in the way:
  - Quoted text and heredoc bodies are ignored, so `gh pr create --body "run git commit"` or `grep "git commit"` is not
    a commit.
  - A crash in prereview.py (as opposed to problems it reports) never blocks; it prints a warning instead.
  - A commit made in some other folder (another repository or checkout) is not checked against this one.

This only covers the mechanical half of the review. The independent reviewer agents are started by the pre-commit-review
skill, which AGENTS.md and the contributing guide tell agents to run before committing.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# git, then any options before the sub-command (-C <dir>, -c <k=v>, --git-dir <dir>, --no-pager ...), then commit.
COMMIT = re.compile(
    r"(?:^|[;&|(\n]\s*|\s)git(?:\.exe)?"
    r"(?:\s+(?:-[Cc]\s+\S+|--(?:git-dir|work-tree|namespace|exec-path)(?:\s+|=)\S+|--?[\w.-]+(?:=\S*)?))*"
    r"\s+commit(?![\w-])"
)


def plain(command):
    """The command without heredoc bodies and quoted strings (their contents are not commands)."""
    command = re.sub(r"<<-?\s*['\"]?(\w+)['\"]?[^\n]*\n.*?\n\s*\1\b", "", command, flags=re.S)
    command = re.sub(r'"(?:[^"\\]|\\.)*"|\'[^\']*\'', '""', command)
    return command


def is_commit(command):
    return bool(COMMIT.search(plain(command)))


def elsewhere(call):
    """True when the tool call runs in a folder that is not part of this checkout."""
    cwd = call.get("cwd")
    if not cwd:
        return False
    try:
        Path(cwd).resolve().relative_to(ROOT)
        return False
    except (ValueError, OSError):
        return True


def main():
    try:
        call = json.load(sys.stdin)
    except ValueError:
        return 0
    if not isinstance(call, dict):
        return 0
    command = (call.get("tool_input") or {}).get("command")
    if not isinstance(command, str) or not is_commit(command) or elsewhere(call):
        return 0
    result = subprocess.run([sys.executable, "tools/prereview.py"], cwd=ROOT, capture_output=True, text=True)
    if result.returncode == 0:
        return 0
    if result.returncode != 1 or not result.stdout.rstrip().endswith("problem(s)"):
        sys.stderr.write("Warning: tools/prereview.py failed to run, so the commit was not checked.\n" + result.stderr)
        return 0
    sys.stderr.write(
        "Commit blocked: the pre-commit checks found problems. Fix them, then run the pre-commit-review skill "
        "before committing.\n\n" + result.stdout
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
