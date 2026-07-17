#!/usr/bin/env bash
# evals/guards.test.sh — deterministic eval battery for the enforcement hooks.
#
# Every guard is exercised against synthetic blocked/allowed tool-call payloads.
# Run from the repo root:  bash evals/guards.test.sh
# Exit 0 = all pass. Exit 1 = failures (listed).
#
# This is the regression floor: any change to hooks/ must keep this green, and
# every guard bug found in the field gets a case added here (compound-learnings).
#
# Note: secret-like fixtures are ASSEMBLED AT RUNTIME (string concatenation) so
# this file never contains a literal secret-shaped string — otherwise secret
# scanners (including our own guard-secrets.sh) rightly refuse to write it.

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
H="$ROOT/hooks"
PASS=0; FAIL=0

# Runtime-assembled fixtures (never literal in this file)
AWS_KEY="AKIA""ABCDEFGHIJKLMNOP"
ANT_KEY="sk-""ant-api03-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
GH_PAT="ghp_""ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef123456"
PEM_HDR="-----BEGIN RSA ""PRIVATE KEY-----"
DB_URL="postgres""://admin:hunter2@db.internal/prod"
JWT="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"".""eyJzdWIiOiIxMjM0NTY3ODkwIn0"".""dozjgNryP4J3jVmNHl0w5N3XgL0n3I9PlFUP0THsR8U"

t() { # name  expected_exit  hook  json
  local name="$1" want="$2" hook="$3" json="$4"
  local got
  printf '%s' "$json" | bash "$hook" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    PASS=$((PASS+1)); echo "PASS ($got): $name"
  else
    FAIL=$((FAIL+1)); echo "FAIL (got $got, want $want): $name"
  fi
}

tc() { # name expected_exit event policy json -- Codex native adapter
  local name="$1" want="$2" event="$3" policy="$4" json="$5"
  local got
  printf '%s' "$json" | "$ROOT/adapters/run-hook.sh" codex "$event" "$policy" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    PASS=$((PASS+1)); echo "PASS ($got): $name"
  else
    FAIL=$((FAIL+1)); echo "FAIL (got $got, want $want): $name"
  fi
}

wjson() { # file_path content -> Write payload (jq-safe encoding)
  jq -cn --arg fp "$1" --arg c "$2" '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}'
}

pjson() { # patch -> Codex apply_patch payload
  jq -cn --arg c "$1" '{tool_name:"apply_patch",tool_input:{command:$c}}'
}

echo "── guard-secrets ──────────────────────────────────────────"
t "blocks AWS access key"        2 "$H/guard-secrets.sh" "$(wjson config.md "key = $AWS_KEY")"
t "blocks Anthropic API key"     2 "$H/guard-secrets.sh" "$(wjson x.ts "const k = \"$ANT_KEY\"")"
t "blocks GitHub PAT"            2 "$H/guard-secrets.sh" "$(wjson ci.md "$GH_PAT")"
t "blocks private key block"     2 "$H/guard-secrets.sh" "$(wjson k.md "$PEM_HDR")"
t "blocks db url with password"  2 "$H/guard-secrets.sh" "$(wjson a.yml "url: $DB_URL")"
t "blocks JWT-looking token"     2 "$H/guard-secrets.sh" "$(wjson t.md "$JWT")"
tc "blocks secret in Codex patch" 2 pre_edit guard-secrets.sh "$(pjson $'*** Begin Patch\n*** Add File: config.md\n+key = '"$AWS_KEY"$'\n*** End Patch')"
tc "allows removing secret in Codex patch" 0 pre_edit guard-secrets.sh "$(pjson $'*** Begin Patch\n*** Update File: config.md\n@@\n-key = '"$AWS_KEY"$'\n+key = $API_KEY\n*** End Patch')"
t "allows clean content"         0 "$H/guard-secrets.sh" "$(wjson readme.md 'just docs, use $API_KEY from env')"
t "allows empty input"           0 "$H/guard-secrets.sh" '{}'

echo "── guard-protected-paths ──────────────────────────────────"
t "blocks .env"                   2 "$H/guard-protected-paths.sh" "$(wjson .env 'X=1')"
t "blocks nested .env.production" 2 "$H/guard-protected-paths.sh" "$(wjson app/.env.production 'X=1')"
t "blocks package-lock.json"      2 "$H/guard-protected-paths.sh" "$(wjson package-lock.json '{}')"
t "blocks composer.lock"          2 "$H/guard-protected-paths.sh" "$(wjson composer.lock '{}')"
t "blocks migrations dir"         2 "$H/guard-protected-paths.sh" "$(wjson db/migrations/001_init.sql 'ALTER')"
t "blocks vendored code"          2 "$H/guard-protected-paths.sh" "$(wjson vendor/pkg/x.php '<?php')"
tc "blocks Codex patch to .env" 2 pre_edit guard-protected-paths.sh "$(pjson $'*** Begin Patch\n*** Update File: app/.env.production\n@@\n-X=1\n+X=2\n*** End Patch')"
tc "blocks Codex rename to lockfile" 2 pre_edit guard-protected-paths.sh "$(pjson $'*** Begin Patch\n*** Update File: package.json\n*** Move to: package-lock.json\n@@\n-{}\n+{}\n*** End Patch')"
tc "allows normal Codex patch" 0 pre_edit guard-protected-paths.sh "$(pjson $'*** Begin Patch\n*** Add File: src/clean.ts\n+export const clean = true\n*** End Patch')"
t "allows env-helper source"      0 "$H/guard-protected-paths.sh" "$(wjson src/env-helper.ts 'export const x=1')"
t "allows normal markdown"        0 "$H/guard-protected-paths.sh" "$(wjson docs/notes.md 'hi')"

bjson() { jq -cn --arg c "$1" '{tool_input:{command:$c}}'; }

echo "── guard-destructive ──────────────────────────────────────"
t "blocks rm -rf / (with args)"  2 "$H/guard-destructive.sh" "$(bjson 'rm -rf / --no-preserve-root')"
t "blocks rm -rf / (bare)"       2 "$H/guard-destructive.sh" "$(bjson 'rm -rf /')"
t "blocks rm -rf absolute path"  2 "$H/guard-destructive.sh" "$(bjson 'rm -rf /tmp/x')"
t "blocks rm -rf ~"              2 "$H/guard-destructive.sh" "$(bjson 'rm -rf ~/Projects')"
t "blocks rm -rf .."             2 "$H/guard-destructive.sh" "$(bjson 'rm -rf ../other-repo')"
t "allows rm -rf ./build"        0 "$H/guard-destructive.sh" "$(bjson 'rm -rf ./build')"
t "allows rm -rf dist"           0 "$H/guard-destructive.sh" "$(bjson 'rm -rf dist node_modules')"
t "blocks force-push main"       2 "$H/guard-destructive.sh" "$(bjson 'git push --force origin main')"
t "blocks -f push to master"     2 "$H/guard-destructive.sh" "$(bjson 'git push -f origin master')"
t "blocks branchless force-push" 2 "$H/guard-destructive.sh" "$(bjson 'git push --force')"
t "blocks remote-only -f push"   2 "$H/guard-destructive.sh" "$(bjson 'git push -f origin')"
t "blocks force-push feature"    2 "$H/guard-destructive.sh" "$(bjson 'git push --force origin feat/x')"
t "allows force-with-lease feat" 0 "$H/guard-destructive.sh" "$(bjson 'git push --force-with-lease origin feat/x')"
t "blocks hard reset main"       2 "$H/guard-destructive.sh" "$(bjson 'git reset --hard origin/main')"
t "blocks branch -D master"      2 "$H/guard-destructive.sh" "$(bjson 'git branch -D master')"
t "blocks filter-branch"         2 "$H/guard-destructive.sh" "$(bjson 'git filter-branch --tree-filter x HEAD')"
t "blocks mkfs"                  2 "$H/guard-destructive.sh" "$(bjson 'mkfs.ext4 /dev/sda1')"
t "blocks dd to device"          2 "$H/guard-destructive.sh" "$(bjson 'dd if=img.iso of=/dev/disk2')"
t "blocks DROP TABLE via psql"   2 "$H/guard-destructive.sh" "$(bjson 'echo "DROP TABLE users;" | psql prod')"
t "allows normal git"            0 "$H/guard-destructive.sh" "$(bjson 'git status && git diff')"
t "allows grepping for SQL"      0 "$H/guard-destructive.sh" "$(bjson 'grep -r "DROP TABLE" ./migrations')"

echo "── escape hatch ───────────────────────────────────────────"
printf '%s' "$(bjson 'git push --force origin main')" | HARNESS_ALLOW_DESTRUCTIVE=1 bash "$H/guard-destructive.sh" >/dev/null 2>&1
if [ $? = 0 ]; then PASS=$((PASS+1)); echo "PASS (0): HARNESS_ALLOW_DESTRUCTIVE=1 bypasses"; else FAIL=$((FAIL+1)); echo "FAIL: escape hatch broken"; fi

echo "── stop-verify-gate ───────────────────────────────────────"
TMP=$(mktemp -d)
pushd "$TMP" >/dev/null
git init -q
printf '{}' | bash "$H/stop-verify-gate.sh" >/dev/null 2>&1
if [ $? = 0 ]; then PASS=$((PASS+1)); echo "PASS (0): gate off when unconfigured"; else FAIL=$((FAIL+1)); echo "FAIL: gate should be off when unconfigured"; fi
mkdir -p .harness && printf 'false\n' > .harness/check
printf '{}' | bash "$H/stop-verify-gate.sh" >/dev/null 2>&1
if [ $? = 2 ]; then PASS=$((PASS+1)); echo "PASS (2): blocks stop on failing check"; else FAIL=$((FAIL+1)); echo "FAIL: should block on failing check"; fi
mkdir -p nested
pushd nested >/dev/null
printf '{}' | bash "$H/stop-verify-gate.sh" >/dev/null 2>&1
if [ $? = 2 ]; then PASS=$((PASS+1)); echo "PASS (2): nested CWD finds root check"; else FAIL=$((FAIL+1)); echo "FAIL: nested CWD missed root check"; fi
popd >/dev/null
printf '{"stop_hook_active":true}' | bash "$H/stop-verify-gate.sh" >/dev/null 2>&1
if [ $? = 0 ]; then PASS=$((PASS+1)); echo "PASS (0): loop protection allows second stop"; else FAIL=$((FAIL+1)); echo "FAIL: loop protection broken"; fi
printf 'true\n' > .harness/check
printf '{}' | bash "$H/stop-verify-gate.sh" >/dev/null 2>&1
if [ $? = 0 ]; then PASS=$((PASS+1)); echo "PASS (0): allows stop on green check"; else FAIL=$((FAIL+1)); echo "FAIL: should allow on green check"; fi
HARNESS_CHECK=false bash -c "printf '{}' | bash '$H/stop-verify-gate.sh'" >/dev/null 2>&1
if [ $? = 2 ]; then PASS=$((PASS+1)); echo "PASS (2): HARNESS_CHECK env respected"; else FAIL=$((FAIL+1)); echo "FAIL: HARNESS_CHECK env ignored"; fi
popd >/dev/null
rm -rf "$TMP"

echo "── post-edit-format ───────────────────────────────────────"
t "formatter no-ops on missing file" 0 "$H/post-edit-format.sh" "$(bjson x | jq -c '{tool_input:{file_path:"/nonexistent/x.ts"}}')"
tc "formatter accepts Codex patch" 0 post_edit post-edit-format.sh "$(pjson $'*** Begin Patch\n*** Update File: /nonexistent/x.ts\n@@\n-old\n+new\n*** End Patch')"
t "formatter no-ops on empty input"  0 "$H/post-edit-format.sh" '{}'

echo "────────────────────────────────────────────────────────────"
echo "guards.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] || exit 1
