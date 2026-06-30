# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is this?

A Claude Code **plugin** that implements an autonomous experiment loop. Port of [pi-autoresearch](https://github.com/davebcn87/pi-autoresearch) — no MCP server, pure skill + hooks.

## Project structure

```
.claude-plugin/plugin.json       # Plugin manifest (name, version, keywords)
.claude-plugin/marketplace.json  # Marketplace catalog (lets this repo be added as a marketplace source)
skills/autoresearch/SKILL.md     # Core skill: setup, JSONL protocol, run/log/loop logic
skills/git-repo/SKILL.md         # Scaffold skill: detect stack, generate bench harness, hand off
commands/autoresearch.md         # /autoresearch slash command (start, resume, off)
commands/git-repo.md             # /git-repo slash command (path arg optional)
hooks/hooks.json                 # Hook definitions (plugin format)
hooks/autoresearch-context.sh    # UserPromptSubmit hook — injects context when active
examples/                        # Fastball velocity prediction demo files
experiments/                     # Gitignored — experiment worklogs go here
```

## Skills vs Commands

- **Skills** (`skills/<name>/SKILL.md`) — model-invoked; discovered by the agent via their frontmatter `name` + `description`. Invoked when the agent decides a skill matches the task, or via `Invoke skill: <name>`.
- **Commands** (`commands/<name>.md`) — user-invoked via `/pluginname:cmdname`; flat `.md` with optional YAML frontmatter (`description`, `argument-hint`, `allowed-tools`). `$ARGUMENTS` is substituted with the user's slash command arguments.

## Testing locally

```bash
# Load plugin for one session only (no install):
claude --plugin-dir /path/to/autoresearch-claude-code

# Or install permanently then reload:
claude plugin marketplace add /path/to/autoresearch-claude-code
claude plugin install autoresearch@autoresearch
```

## Key conventions

- **SKILL.md is the source of truth** for all behavior. The original 3 MCP tools (`init_experiment`, `run_experiment`, `log_experiment`) are encoded as instructions the agent follows using Bash/Read/Write.
- **JSONL format** in `autoresearch.jsonl` is the state format. Config headers start segments, result lines track experiments. See SKILL.md for exact JSON schemas.
- **Git commits on keep** use a `Result: {...}` trailer in the commit message body.
- **Dashboard** is written to `autoresearch-dashboard.md` (file-based, not TUI).
- **Worklog** is written to `experiments/worklog.md` — narrative log of experiments and insights, survives context compactions.
- **Ideas backlog** is written to `autoresearch.ideas.md` — promising ideas deferred for later; pruned when the loop resumes.
- The hook script must output to stdout (that's how Claude Code hooks inject context).
- The hook fires on every `UserPromptSubmit` but only injects context when `autoresearch.md` exists and `.autoresearch-off` does not.
- All experiment artifacts (`autoresearch.jsonl`, `autoresearch-dashboard.md`, `autoresearch.md`, `autoresearch.sh`, `autoresearch_bench.py`, `autoresearch.ideas.md`, `experiments/`, `plots/`) are gitignored.

## Editing tips

- If changing the JSONL schema, update both the "JSONL State Protocol" and "Logging Results" sections in `skills/autoresearch/SKILL.md` — they must stay in sync.
- The command file uses `$ARGUMENTS` which Claude Code substitutes with the user's slash command arguments.
- Hook scripts run in the user's cwd, not the repo directory.
- `hooks/hooks.json` defines hooks in plugin format. The shell script path uses `${CLAUDE_PLUGIN_ROOT}` which resolves at runtime.
- `git-repo` skill emits a Python benchmark (`autoresearch_bench.py`) and calls `autoresearch.sh` which delegates to it; both are gitignored in the user's project.
