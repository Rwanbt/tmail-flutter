#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Test the same helper used by the disposable QA TLS/JWT setup.
source "$SCRIPT_DIR/private-files.sh"

test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT

for key in jwt_privatekey qa-ca.key tls.key; do
  file="$test_dir/$key"
  printf '%s\n' 'NOT_A_REAL_SECRET' > "$file"
  chmod 644 -- "$file"
  secure_private_file "$file"
  actual="$(stat -c '%a' "$file")"
  if [[ "$actual" != 600 ]]; then
    printf 'QA secret file %s is readable by another user (%s)\n' "$key" "$actual" >&2
    exit 1
  fi
done

if secure_private_file "$test_dir/absent-key"; then
  echo 'Missing private QA key was incorrectly accepted' >&2
  exit 1
fi
echo 'All QA JWT and TLS private key permission checks passed'
