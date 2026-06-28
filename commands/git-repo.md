---
description: Start research experiments on any codebase — detects tech stack, generates a Python benchmark artifact, and wires up the autoresearch loop
argument-hint: [path/to/repo | .]
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

You are setting up autoresearch for a git repository.

## Handle arguments

Arguments: $ARGUMENTS

### If arguments is empty or "."

Use the current working directory as the repository path.

### If arguments is a path

Use that path as the repository root. Verify it exists:
```bash
test -d "$ARGUMENTS" && echo "EXISTS" || echo "PATH_NOT_FOUND"
```

If not found, tell the user and stop.

---

## Run the git-repo skill

Invoke the `git-repo` skill with the resolved repository path.
