---
description: Scaffold autoresearch for any git repo — detects tech stack, generates a Python benchmark artifact, and wires up the experiment loop
argument-hint: [path/to/repo]
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Skill
---

# Git-Repo Command

Set up autoresearch for a git repository.

## Handle arguments

Arguments: $ARGUMENTS

### If arguments is empty or "."

Use the current working directory as the repository root.

### If arguments is a path

```bash
test -d "$ARGUMENTS" && echo "EXISTS" || echo "NOT_FOUND"
```

If NOT_FOUND, tell the user and stop.

Change into the repo directory before proceeding:

```bash
cd "$ARGUMENTS"
```

---

## Run the git-repo skill

Invoke the `git-repo` skill to detect the stack, generate the benchmark, and start the loop.
