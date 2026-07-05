---
name: alignment
description: Align MARK AGENTS.md, Cursor rules/skills/plans, Greptile config, and validation instructions with current executable repo state.
---

# MARK AGENTS Alignment

Use this skill when editing `AGENTS.md`, `contracts/AGENTS.md`, `.cursor/**`, `greptile.json`, or docs that define agent behavior, validation routing, CI expectations, or security review workflow.

## Workflow

1. Inspect current executable state:

   ```bash
   node -e "const p=require('./package.json'); console.log(Object.keys(p.scripts).sort().join('\n'))"
   rg -n '^\[tasks\.' .mise.toml
   rg -n '^[a-zA-Z0-9_.:-]+:' contracts/Makefile
   find .github/workflows -maxdepth 1 -type f | sort
   find contracts/src -maxdepth 2 -type d | sort
   ```

2. Compare behavior docs:

   - `AGENTS.md`
   - `contracts/AGENTS.md`
   - `.cursor/rules/*.mdc`
   - `.cursor/skills/*/SKILL.md`
   - `greptile.json`

3. Fix drift conservatively:

   - Remove nonexistent commands.
   - Separate local checks from GitHub CI checks.
   - Keep security invariants stronger than convenience.
   - Link domain-specific behavior to the relevant source files.

4. Validate:

   ```bash
   pnpm exec prettier --check AGENTS.md contracts/AGENTS.md .cursor/**/*.md .cursor/**/*.mdc
   node -e "const fs=require('fs'); JSON.parse(fs.readFileSync('greptile.json','utf8')); console.log('greptile json ok')"
   ```

5. Run local Greptile review when available:

   ```bash
   greptile review --agent --diff --context=8
   ```

## Reporting

Report changed behavior surfaces, validation commands, Greptile result, and any unavailable tools or environment blockers.
