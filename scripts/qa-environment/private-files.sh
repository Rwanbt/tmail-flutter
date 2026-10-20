#!/usr/bin/env bash

# QA certificates and JWT credentials must not be readable by other local
# users. The disposable nginx/backend containers run as root and can still
# consume the bind-mounted private files.
secure_private_file() {
  local file="${1:?private file path required}"
  if [[ ! -f "$file" ]]; then
    printf 'Missing private QA file: %s\n' "$file" >&2
    return 1
  fi
  chmod 600 -- "$file"
}
