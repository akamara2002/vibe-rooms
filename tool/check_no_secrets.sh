#!/usr/bin/env bash
# Fails when a file that is (or is about to be) committed contains something
# that looks like a secret:
#   * a Supabase key prefix: sb_publishable_... or sb_secret_...
#   * a JWT-looking string (eyJ followed by a long base64url segment)
#   * the project's Supabase URL, read from env.json (skipped when env.json
#     does not exist, e.g. in CI)
# It prints only the file name and the kind of match, NEVER the matching text,
# the URL or any key. Binary files are skipped.
#
# Run from the repository root:  tool/check_no_secrets.sh
set -u

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 2

# Tracked files plus new files that are not ignored (so it also guards the
# commit you are about to make).
files=$(git ls-files --cached --others --exclude-standard) || exit 2

fail=0
report() { echo "FOUND $1 in $2"; fail=1; }

scan() { # <kind> <extended regex>
  local kind="$1" pattern="$2" file
  while IFS= read -r file; do
    [ -f "$file" ] || continue
    if grep -Iq -E -e "$pattern" -- "$file" 2>/dev/null; then
      report "$kind" "$file"
    fi
  done <<<"$files"
}

scan "a Supabase key prefix" 'sb_(publishable|secret)_[A-Za-z0-9_-]{16,}'
scan "a JWT-looking string" 'eyJ[A-Za-z0-9_-]{30,}'
scan "a database URL with a password" 'postgres(ql)?://[^[:space:]:@/]+:[^[:space:]@]{4,}@'
scan "a service_role key assignment" 'service_role["'"'"' ]*[:=]["'"'"' ]*[A-Za-z0-9_.-]{30,}'

# The project URL from env.json. Read inside python so it never reaches the
# command line or the output.
if [ -f env.json ] && ! command -v python3 >/dev/null 2>&1; then
  echo "note: python3 not found, skipped the project URL check"
elif [ -f env.json ]; then
  while IFS= read -r file; do
    [ -f "$file" ] || continue
    [ "$file" = "env.json" ] && continue
    hit=$(FILE="$file" python3 -I - <<'PY' 2>/dev/null
import json, os
try:
    env = json.load(open("env.json"))
except Exception:
    raise SystemExit(0)
urls = [v for k, v in env.items()
        if "URL" in k.upper() and isinstance(v, str) and len(v) > 8]
try:
    data = open(os.environ["FILE"], "rb").read()
except Exception:
    raise SystemExit(0)
if b"\0" in data[:4096]:
    raise SystemExit(0)  # binary
if any(u.encode() in data for u in urls):
    print("hit")
PY
)
    [ "$hit" = "hit" ] && report "the Supabase URL from env.json" "$file"
  done <<<"$files"
else
  echo "note: env.json not found, skipped the project URL check"
fi

if [ "$fail" -ne 0 ]; then
  echo "FAILED: remove the secret(s) above (and rotate the key if it was committed)."
  exit 1
fi
echo "OK: no secrets found in $(printf '%s\n' "$files" | grep -c .) files"
