#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
from pathlib import Path
import re
import sys

apply_governance = Path("scripts/github/apply-governance.sh").read_text()
branching = Path("BRANCHING.md").read_text()
checklist = Path(".github/PRODUCTION_GOVERNANCE_CHECKLIST.md").read_text()


def parse_checks(var_name: str) -> list[str]:
    pattern = rf"{var_name}='\[(.*?)\]'"
    m = re.search(pattern, apply_governance, re.S)
    if not m:
        raise RuntimeError(f"Could not parse {var_name} from apply-governance.sh")
    block = m.group(1)
    return re.findall(r'"([^"]+)"', block)


def parse_branching_section(title: str) -> list[str]:
    # Capture bullet lines after a section header until the next header.
    pattern = rf"### {re.escape(title)}\n\n(.*?)(?:\n### |\n## |\Z)"
    m = re.search(pattern, branching, re.S)
    if not m:
        raise RuntimeError(f"Could not parse section '{title}' from BRANCHING.md")
    block = m.group(1)
    return [line.strip()[3:-1] if line.strip().startswith("- `") and line.strip().endswith("`") else line.strip()[2:]
            for line in block.splitlines() if line.strip().startswith("- ")]


def parse_checklist_section(title: str) -> list[str]:
    pattern = rf"## {re.escape(title)}\n\n(.*?)(?:\n## |\Z)"
    m = re.search(pattern, checklist, re.S)
    if not m:
        raise RuntimeError(f"Could not parse section '{title}' from checklist")
    block = m.group(1)
    in_checks = False
    checks = []
    for raw in block.splitlines():
        line = raw.strip()
        if line == "- Add required checks:":
            in_checks = True
            continue
        if in_checks:
            if line.startswith("- `") and line.endswith("`"):
                checks.append(line[3:-1])
                continue
            if line.startswith("- ") and not line.startswith("- `"):
                break
    return checks


def ensure_contains_all(container: list[str], expected: list[str], label: str) -> list[str]:
    missing = [x for x in expected if x not in container]
    if missing:
        return [f"{label} missing: {x}" for x in missing]
    return []


errors = []
dev_expected = parse_checks("DEV_CHECKS_JSON")
main_expected = parse_checks("MAIN_CHECKS_JSON")

branching_dev = parse_branching_section("PRs into `dev`")
branching_main = parse_branching_section("PRs into `main` (release candidate)")
errors += ensure_contains_all(branching_dev, dev_expected, "BRANCHING.md dev matrix")
errors += ensure_contains_all(branching_main, main_expected, "BRANCHING.md main matrix")

checklist_main = parse_checklist_section("1) Protect `main` branch")
checklist_dev = parse_checklist_section("2) Protect `dev` branch")
errors += ensure_contains_all(checklist_main, main_expected, "Governance checklist main required checks")
errors += ensure_contains_all(checklist_dev, dev_expected, "Governance checklist dev required checks")

if errors:
    print("Governance policy drift detected:")
    for err in errors:
        print(f"- {err}")
    sys.exit(1)

print("Governance policy validation PASSED")
PY
