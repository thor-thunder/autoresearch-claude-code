---
name: run-autoresearch-claude-code
description: Validate, test, and install the autoresearch-claude-code plugin. Use when asked to run, test, verify, or install this plugin, or to confirm the hook and skills work correctly.
---

`autoresearch-claude-code` is a Claude Code plugin — there is no server or GUI. "Running" it means validating the plugin structure, exercising the hook script, and confirming the install.

## Smoke test (agent path)

Run from the repo root:

```bash
bash .claude/skills/run-autoresearch-claude-code/smoke.sh
```

This verifies all 16 checks:
- JSON manifests valid (plugin.json, marketplace.json, hooks.json)
- Both skills have `name:` frontmatter
- Both commands exist and contain `$ARGUMENTS`
- Hook is silent when `autoresearch.md` absent
- Hook injects context when `autoresearch.md` present
- Hook respects `.autoresearch-off` sentinel
- `autoresearch@autoresearch` shows as installed in `claude plugin list`

Exit 0 = all pass. Exit 1 = at least one failure (printed inline).

## Install from this repo

```bash
claude plugin marketplace add /home/user/autoresearch-claude-code
claude plugin install autoresearch@autoresearch
claude plugin list
```

Expected output includes `autoresearch@autoresearch` with `Status: √ enabled`.

## Test session-load (one-shot)

```bash
claude --plugin-dir /home/user/autoresearch-claude-code
```

Then inside the session: `/autoresearch:autoresearch off` should create `.autoresearch-off`.

## Verify hook manually

```bash
# Active (autoresearch.md present) — should print context block
echo "# test" > /tmp/autoresearch.md
(cd /tmp && bash /home/user/autoresearch-claude-code/hooks/autoresearch-context.sh)
rm /tmp/autoresearch.md

# Inactive — should print nothing
bash hooks/autoresearch-context.sh
```

## Gotchas

- Hook script runs in the **user's cwd** (the project under research), not the plugin repo. The bash path must be absolute or resolved via `${CLAUDE_PLUGIN_ROOT}` (which Claude Code substitutes at hook dispatch time).
- The `plugins` array in `~/.claude/settings.json` takes effect only after a session restart. Use `claude plugin marketplace add` + `claude plugin install` for immediate effect within a session.
- In remote execution environments, `~/.claude/` may not persist between sessions. To auto-register the plugin for any agent opening this repo, add to `.claude/settings.json` in the project root (not yet done).
