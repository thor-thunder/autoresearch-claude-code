---
name: git-repo
description: Scaffold an autoresearch experiment for any codebase by detecting its tech stack and generating a Python benchmark artifact. Use when (1) the user's message contains the word "research", or (2) any experiment/benchmark/optimization request is made against a local codebase.
---

# Git Repo Skill

Inspect the repository, detect its tech stack, generate a Python benchmark artifact, and wire it into the autoresearch loop.

## Step 1 — Detect tech stack

Run these in parallel:

```bash
# Language fingerprints
ls -1
find . -maxdepth 2 -name "*.py" | head -5
find . -maxdepth 2 -name "*.js" -o -name "*.ts" | head -5
find . -maxdepth 2 -name "*.go" | head -5
find . -maxdepth 2 -name "*.rs" | head -5
```

```bash
# Tooling fingerprints
ls pyproject.toml setup.py setup.cfg requirements*.txt Makefile package.json go.mod Cargo.toml 2>/dev/null
cat pyproject.toml 2>/dev/null || cat setup.py 2>/dev/null || true
```

```bash
# Test framework
grep -r "import pytest\|unittest\|jest\|testing.T\|#\[test\]" --include="*.py" --include="*.js" --include="*.go" --include="*.rs" -l | head -10
```

From the output, classify the repo into one of:
- **python-ml** — has numpy/torch/sklearn/pandas imports
- **python-generic** — Python but no ML libs
- **node** — package.json present
- **go** — go.mod present
- **rust** — Cargo.toml present
- **unknown** — none of the above

Also identify:
- `TEST_CMD`: the command that runs the test suite (e.g. `pytest`, `npm test`, `go test ./...`)
- `BUILD_CMD`: build step if needed (e.g. `pip install -e .`, `npm ci`)
- `PRIMARY_METRIC`: what to optimize (`test_duration_s`, `accuracy`, `coverage_pct`, `build_time_s`)
- `BEST_DIRECTION`: `lower` (for timing) or `higher` (for accuracy/coverage)

## Step 2 — Ask the user (if needed)

If the stack is ambiguous or `PRIMARY_METRIC` is unclear, ask one focused question:

> "I detected a **{stack}** repo. Should I optimize **test speed** (lower duration) or **accuracy/coverage** (higher %)?"

Otherwise skip this step and proceed.

## Step 3 — Write the Python artifact

Create `autoresearch_bench.py` — the benchmark script that the autoresearch loop will call. Choose the template matching the detected stack.

### Template: python-ml

```python
#!/usr/bin/env python3
"""Autoresearch benchmark — python-ml stack."""
import subprocess, time, re, sys

def run_benchmark():
    start = time.perf_counter()
    result = subprocess.run(
        ["python", "-m", "pytest", "--tb=no", "-q", "--no-header"],
        capture_output=True, text=True
    )
    elapsed = time.perf_counter() - start

    # Parse pytest output for pass count and timing
    passed = len(re.findall(r" PASSED", result.stdout))
    failed = len(re.findall(r" FAILED", result.stdout))
    total  = passed + failed

    if result.returncode != 0 and total == 0:
        print("BENCHMARK_ERROR: tests failed to collect", file=sys.stderr)
        sys.exit(1)

    coverage = (passed / total * 100) if total else 0.0
    print(f"METRIC test_duration_s={elapsed:.3f}")
    print(f"METRIC test_pass_rate={coverage:.1f}")
    print(f"METRIC tests_passed={passed}")

if __name__ == "__main__":
    run_benchmark()
```

### Template: python-generic

```python
#!/usr/bin/env python3
"""Autoresearch benchmark — python-generic stack."""
import subprocess, time, sys

def run_benchmark():
    start = time.perf_counter()
    result = subprocess.run(
        ["python", "-m", "pytest", "--tb=short", "-q"],
        capture_output=True, text=True
    )
    elapsed = time.perf_counter() - start

    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        sys.exit(1)

    print(f"METRIC test_duration_s={elapsed:.3f}")

if __name__ == "__main__":
    run_benchmark()
```

### Template: node

```python
#!/usr/bin/env python3
"""Autoresearch benchmark — node stack."""
import subprocess, time, sys

def run_benchmark():
    start = time.perf_counter()
    result = subprocess.run(["npm", "test", "--", "--passWithNoTests"],
                            capture_output=True, text=True)
    elapsed = time.perf_counter() - start

    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        sys.exit(1)

    print(f"METRIC test_duration_s={elapsed:.3f}")

if __name__ == "__main__":
    run_benchmark()
```

### Template: go

```python
#!/usr/bin/env python3
"""Autoresearch benchmark — go stack."""
import subprocess, time, re, sys

def run_benchmark():
    start = time.perf_counter()
    result = subprocess.run(["go", "test", "./...", "-v", "-count=1"],
                            capture_output=True, text=True)
    elapsed = time.perf_counter() - start

    passed = len(re.findall(r"^--- PASS", result.stdout, re.MULTILINE))
    failed = len(re.findall(r"^--- FAIL", result.stdout, re.MULTILINE))

    if result.returncode != 0 and failed == 0:
        print(result.stderr, file=sys.stderr)
        sys.exit(1)

    pass_rate = (passed / (passed + failed) * 100) if (passed + failed) else 100.0
    print(f"METRIC test_duration_s={elapsed:.3f}")
    print(f"METRIC pass_rate={pass_rate:.1f}")

if __name__ == "__main__":
    run_benchmark()
```

### Template: unknown

Use `python-generic` template but set `TEST_CMD` to `make test` or the closest available runner.

After writing `autoresearch_bench.py`, make it executable:

```bash
chmod +x autoresearch_bench.py
```

## Step 4 — Write autoresearch.sh

```bash
cat > autoresearch.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Syntax check
python3 -c "import py_compile; py_compile.compile('autoresearch_bench.py', doraise=True)" 2>&1 || { echo "Syntax error in autoresearch_bench.py"; exit 1; }

# Run benchmark
python3 autoresearch_bench.py
EOF
chmod +x autoresearch.sh
```

If the stack is not Python, replace the syntax check with the appropriate pre-check (e.g. `node --check`, `go vet ./...`).

## Step 5 — Create autoresearch.md

Use the detected metadata to fill in this template:

```markdown
# Autoresearch: optimize {PRIMARY_METRIC} in {repo_name}

## Objective
Minimize/maximize {PRIMARY_METRIC} for the {stack} codebase in this repo.
The benchmark is `autoresearch_bench.py`, called via `./autoresearch.sh`.

## Metrics
- **Primary**: {PRIMARY_METRIC} ({unit}, {BEST_DIRECTION} is better)
- **Secondary**: (add as discovered)

## How to Run
`./autoresearch.sh` — outputs `METRIC name=number` lines.

## Files in Scope
- `autoresearch_bench.py` — benchmark harness (may be tuned)
- Source files identified: (list them here)

## Off Limits
- Test files themselves (unless the goal is to add coverage)
- Lock files, CI config

## Constraints
- All existing tests must continue to pass
- No new external dependencies without approval

## What's Been Tried
(populated during the loop)
```

## Step 6 — Initialize and hand off to autoresearch

```bash
# Initialize JSONL state
echo "{\"type\":\"config\",\"name\":\"$(basename $PWD)\",\"metricName\":\"{PRIMARY_METRIC}\",\"metricUnit\":\"{unit}\",\"bestDirection\":\"{BEST_DIRECTION}\"}" > autoresearch.jsonl

mkdir -p experiments
```

Then invoke the `autoresearch` skill to take over:

```
Invoke skill: autoresearch
```

The autoresearch skill will run the baseline, log it, and start the experiment loop.
