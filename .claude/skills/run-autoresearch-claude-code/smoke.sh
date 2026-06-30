#!/usr/bin/env bash
# Smoke test for autoresearch-claude-code plugin.
# Run from the repo root: bash .claude/skills/run-autoresearch-claude-code/smoke.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0

check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS  $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL  $label"
    FAIL=$((FAIL+1))
  fi
}

echo "=== autoresearch-claude-code smoke test ==="
echo ""

echo "--- Manifests ---"
check "plugin.json valid JSON"      python3 -c "import json; json.load(open('.claude-plugin/plugin.json'))"
check "marketplace.json valid JSON" python3 -c "import json; json.load(open('.claude-plugin/marketplace.json'))"
check "hooks.json valid JSON"       python3 -c "import json; json.load(open('hooks/hooks.json'))"
check "plugin name matches"         python3 -c "import json; d=json.load(open('.claude-plugin/plugin.json')); assert d['name']=='autoresearch'"

echo ""
echo "--- Skills ---"
check "skills/autoresearch/SKILL.md exists" test -f skills/autoresearch/SKILL.md
check "skills/git-repo/SKILL.md exists"     test -f skills/git-repo/SKILL.md
check "autoresearch SKILL has frontmatter"  grep -q "^name: autoresearch" skills/autoresearch/SKILL.md
check "git-repo SKILL has frontmatter"      grep -q "^name: git-repo" skills/git-repo/SKILL.md

echo ""
echo "--- Commands ---"
check "commands/autoresearch.md exists" test -f commands/autoresearch.md
check "commands/git-repo.md exists"     test -f commands/git-repo.md
check "autoresearch cmd has ARGUMENTS"  grep -q 'ARGUMENTS' commands/autoresearch.md
check "git-repo cmd has ARGUMENTS"      grep -q 'ARGUMENTS' commands/git-repo.md

echo ""
echo "--- Hook script (core runtime behavior) ---"
# No autoresearch.md → hook emits nothing
HOOK_INACTIVE_OUTPUT=$(cd /tmp && bash "$REPO_ROOT/hooks/autoresearch-context.sh" 2>&1)
if [ -z "$HOOK_INACTIVE_OUTPUT" ]; then
  echo "  PASS  hook silent when inactive (no autoresearch.md)"
  PASS=$((PASS+1))
else
  echo "  FAIL  hook should be silent when autoresearch.md absent"
  FAIL=$((FAIL+1))
fi

# With autoresearch.md → hook emits context
echo "# test" > /tmp/autoresearch.md
HOOK_ACTIVE_OUTPUT=$(cd /tmp && bash "$REPO_ROOT/hooks/autoresearch-context.sh" 2>&1)
rm -f /tmp/autoresearch.md
if echo "$HOOK_ACTIVE_OUTPUT" | grep -q "Autoresearch Mode"; then
  echo "  PASS  hook injects context when autoresearch.md present"
  PASS=$((PASS+1))
else
  echo "  FAIL  hook should inject 'Autoresearch Mode' context"
  FAIL=$((FAIL+1))
fi

# .autoresearch-off sentinel suppresses injection
echo "# test" > /tmp/autoresearch.md
touch /tmp/.autoresearch-off
HOOK_PAUSED_OUTPUT=$(cd /tmp && bash "$REPO_ROOT/hooks/autoresearch-context.sh" 2>&1)
rm -f /tmp/autoresearch.md /tmp/.autoresearch-off
if [ -z "$HOOK_PAUSED_OUTPUT" ]; then
  echo "  PASS  hook silent when .autoresearch-off sentinel present"
  PASS=$((PASS+1))
else
  echo "  FAIL  hook should respect .autoresearch-off sentinel"
  FAIL=$((FAIL+1))
fi

echo ""
echo "--- Plugin install ---"
PLUGIN_STATUS=$(claude plugin list 2>&1)
if echo "$PLUGIN_STATUS" | grep -q "autoresearch@autoresearch"; then
  echo "  PASS  autoresearch@autoresearch installed"
  PASS=$((PASS+1))
else
  echo "  WARN  autoresearch not in plugin list (may need: claude plugin marketplace add . && claude plugin install autoresearch@autoresearch)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
