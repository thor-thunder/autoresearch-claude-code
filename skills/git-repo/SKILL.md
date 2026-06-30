---
name: git-repo
description: Scaffold an autoresearch experiment for any codebase by detecting its tech stack and generating a Python benchmark artifact. Use when the user wants to run experiments or optimize something in a local repository.
---

# Git Repo Skill

Inspect the repository, detect its tech stack, generate a benchmark harness, and hand off to the autoresearch loop.

## Step 1 — Detect tech stack

Run these in parallel:

```bash
# Language fingerprints
find . -maxdepth 3 -name "*.py" | head -10
find . -maxdepth 3 \( -name "*.js" -o -name "*.ts" \) | head -10
find . -maxdepth 3 -name "*.go" | head -10
find . -maxdepth 3 -name "*.rs" | head -10
```

```bash
# Tooling fingerprints
ls pyproject.toml setup.py setup.cfg requirements*.txt package.json go.mod Cargo.toml Makefile 2>/dev/null || true
cat pyproject.toml 2>/dev/null || cat setup.py 2>/dev/null || true
```

```bash
# ML library presence
grep -r "import torch\|import tensorflow\|from sklearn\|import xgboost\|import lightgbm\|import numpy\|import pandas" \
  --include="*.py" -l 2>/dev/null | head -10 || true
```

```bash
# Test framework
grep -r "import pytest\|import unittest\|jest\|testing\.T\|#\[test\]" \
  --include="*.py" --include="*.js" --include="*.ts" --include="*.go" --include="*.rs" \
  -l 2>/dev/null | head -10 || true
```

Classify the repo into one of:

| Stack | Signal |
|---|---|
| **python-ml** | numpy/torch/sklearn/pandas/xgboost imports |
| **python-generic** | Python present, no ML libs |
| **node** | `package.json` exists |
| **go** | `go.mod` exists |
| **rust** | `Cargo.toml` exists |
| **unknown** | none of the above |

Also determine:
- `TRAIN_SCRIPT`: the main script to run (e.g. `train.py`, `main.py`, `src/train.py`) — for python-ml stacks
- `TEST_CMD`: test runner command (e.g. `pytest`, `npm test`, `go test ./...`)
- `PRIMARY_METRIC`: what to optimize
  - python-ml optimizing accuracy → `val_accuracy` (higher is better)
  - python-ml optimizing speed → `test_duration_s` (lower is better)
  - python-generic, node, go, rust → `test_duration_s` (lower is better)
- `BEST_DIRECTION`: `lower` or `higher`

## Step 2 — Ask the user (if needed)

If the stack is ambiguous **or** the optimization goal is unclear, ask one focused question. Example:

> "I detected a **python-ml** repo with `train.py`. Should I optimize **model accuracy** (higher val_accuracy) or **training speed** (lower duration)?"

Otherwise skip this step.

## Step 3 — Write `autoresearch_bench.py`

Create the benchmark script. Choose the template matching the detected stack and goal.

### Template: python-ml (accuracy goal)

```python
#!/usr/bin/env python3
"""Autoresearch benchmark — python-ml stack, accuracy target."""
import subprocess, sys, re, time

TRAIN_CMD = ["python3", "train.py"]  # adjust to actual script

METRIC_PATTERNS = [
    (re.compile(r"METRIC\s+(\w+)=([0-9.]+)"), None),  # native autoresearch format
    (re.compile(r"(?:val_accuracy|validation_acc)[=:\s]+([0-9.]+)", re.I), "val_accuracy"),
    (re.compile(r"(?:val_f1|f1_score)[=:\s]+([0-9.]+)", re.I), "val_f1"),
    (re.compile(r"(?:val_loss|validation_loss)[=:\s]+([0-9.]+)", re.I), "val_loss"),
    (re.compile(r"\baccuracy[:\s]+([0-9.]+)", re.I), "val_accuracy"),
]

PRIMARY_METRIC = "val_accuracy"

def run():
    start = time.perf_counter()
    r = subprocess.run(TRAIN_CMD, capture_output=True, text=True)
    elapsed = time.perf_counter() - start
    if r.returncode != 0:
        print(r.stderr[-2000:], file=sys.stderr)
        sys.exit(1)
    combined = r.stdout + "\n" + r.stderr
    metrics = {}
    for line in combined.splitlines():
        m = re.match(r"METRIC\s+(\w+)=([0-9.]+)", line.strip())
        if m:
            metrics[m.group(1)] = float(m.group(2))
    if not metrics:
        for pattern, name in METRIC_PATTERNS[1:]:
            for m in pattern.finditer(combined):
                if name not in metrics:
                    metrics[name] = float(m.group(1))
    if not metrics:
        print("ERROR: no METRIC lines found. Ensure train.py prints: METRIC val_accuracy=0.95", file=sys.stderr)
        sys.exit(1)
    if PRIMARY_METRIC not in metrics:
        first = next(iter(metrics))
        metrics[PRIMARY_METRIC] = metrics[first]
    for k, v in metrics.items():
        print(f"METRIC {k}={v:.6f}")
    print(f"\nDone in {elapsed:.1f}s | {PRIMARY_METRIC}={metrics.get(PRIMARY_METRIC):.4f}", file=sys.stderr)

if __name__ == "__main__":
    run()
```

### Template: python-ml (speed goal) or python-generic

```python
#!/usr/bin/env python3
"""Autoresearch benchmark — python stack, test speed target."""
import subprocess, sys, re, time

def run():
    start = time.perf_counter()
    r = subprocess.run(
        ["python", "-m", "pytest", "--tb=no", "-q", "--no-header"],
        capture_output=True, text=True,
    )
    elapsed = time.perf_counter() - start
    passed = len(re.findall(r" PASSED", r.stdout))
    failed = len(re.findall(r" FAILED", r.stdout))
    total = passed + failed
    if r.returncode != 0 and total == 0:
        print(r.stderr[-1000:], file=sys.stderr)
        sys.exit(1)
    pass_rate = (passed / total * 100) if total else 100.0
    print(f"METRIC test_duration_s={elapsed:.3f}")
    print(f"METRIC pass_rate={pass_rate:.1f}")

if __name__ == "__main__":
    run()
```

### Template: node

```python
#!/usr/bin/env python3
"""Autoresearch benchmark — node stack."""
import subprocess, sys, time

def run():
    start = time.perf_counter()
    r = subprocess.run(["npm", "test", "--", "--passWithNoTests"],
                       capture_output=True, text=True)
    elapsed = time.perf_counter() - start
    if r.returncode != 0:
        print(r.stderr[-1000:], file=sys.stderr)
        sys.exit(1)
    print(f"METRIC test_duration_s={elapsed:.3f}")

if __name__ == "__main__":
    run()
```

### Template: go

```python
#!/usr/bin/env python3
"""Autoresearch benchmark — go stack."""
import subprocess, sys, re, time

def run():
    start = time.perf_counter()
    r = subprocess.run(["go", "test", "./...", "-v", "-count=1"],
                       capture_output=True, text=True)
    elapsed = time.perf_counter() - start
    passed = len(re.findall(r"^--- PASS", r.stdout, re.MULTILINE))
    failed = len(re.findall(r"^--- FAIL", r.stdout, re.MULTILINE))
    if r.returncode != 0 and failed == 0:
        print(r.stderr[-1000:], file=sys.stderr)
        sys.exit(1)
    pass_rate = (passed / (passed + failed) * 100) if (passed + failed) else 100.0
    print(f"METRIC test_duration_s={elapsed:.3f}")
    print(f"METRIC pass_rate={pass_rate:.1f}")

if __name__ == "__main__":
    run()
```

### Template: rust

```python
#!/usr/bin/env python3
"""Autoresearch benchmark — rust stack."""
import subprocess, sys, re, time

def run():
    start = time.perf_counter()
    r = subprocess.run(["cargo", "test"], capture_output=True, text=True)
    elapsed = time.perf_counter() - start
    if r.returncode != 0:
        print(r.stderr[-1000:], file=sys.stderr)
        sys.exit(1)
    passed = len(re.findall(r"test .+ \.\.\. ok", r.stdout))
    print(f"METRIC test_duration_s={elapsed:.3f}")
    print(f"METRIC tests_passed={passed}")

if __name__ == "__main__":
    run()
```

After writing `autoresearch_bench.py`:

```bash
chmod +x autoresearch_bench.py
```

Run it once to confirm it emits at least one `METRIC` line:

```bash
python3 autoresearch_bench.py 2>&1 | head -20
```

If it errors, diagnose and fix before proceeding.

## Step 4 — Write `autoresearch.sh`

```bash
cat > autoresearch.sh << 'SHELL'
#!/usr/bin/env bash
set -euo pipefail
python3 -c "import py_compile; py_compile.compile('autoresearch_bench.py', doraise=True)" \
  || { echo "Syntax error in autoresearch_bench.py"; exit 1; }
python3 autoresearch_bench.py
SHELL
chmod +x autoresearch.sh
```

For non-Python stacks, replace the syntax-check line with `node --check autoresearch_bench.py`, `go vet ./...`, or `cargo check` as appropriate.

## Step 5 — Write `autoresearch.md`

Fill in the detected metadata:

```markdown
# Autoresearch: optimize {PRIMARY_METRIC} in {repo_name}

## Objective
{1-sentence description of what we're optimizing and the workload.}

## Metrics
- **Primary**: {PRIMARY_METRIC} ({unit}, {BEST_DIRECTION} is better)
- **Secondary**: (add as discovered)

## How to Run
`./autoresearch.sh` — outputs `METRIC name=number` lines.

## Files in Scope
- `autoresearch_bench.py` — benchmark harness (safe to tune)
- {list source files the agent may modify}

## Off Limits
- Test files themselves (unless the goal is to add coverage)
- Lock files, CI config, dependency manifests

## Constraints
- All existing tests must pass
- No new external dependencies without user approval

## What's Been Tried
(populated during the loop)
```

## Step 6 — Initialize and hand off

```bash
REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
echo "{\"type\":\"config\",\"name\":\"${REPO_NAME}\",\"metricName\":\"{PRIMARY_METRIC}\",\"metricUnit\":\"{unit}\",\"bestDirection\":\"{BEST_DIRECTION}\"}" \
  > autoresearch.jsonl
mkdir -p experiments
```

Then invoke the `autoresearch` skill:

```
Invoke skill: autoresearch
```

The autoresearch skill will run the baseline, log it, and start the loop.
