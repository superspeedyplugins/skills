#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <plugin-repository>" >&2
    exit 2
fi

repo=$(git -C "$1" rev-parse --show-toplevel)

if command -v sha256sum >/dev/null 2>&1; then sha() { sha256sum; }; else sha() { shasum -a 256; }; fi

{
    printf 'INDEX\n'
    git -C "$repo" ls-files --stage
    printf 'WORKTREE\n'
    git -C "$repo" ls-files --cached --others --exclude-standard |
        LC_ALL=C sort |
        while IFS= read -r relative_path; do
            [ -f "$repo/$relative_path" ] || continue
            file_hash=$(sha < "$repo/$relative_path" | awk '{print $1}')
            printf '%s  %s\n' "$file_hash" "$relative_path"
        done
    printf 'SUBMODULES\n'
    git -C "$repo" submodule status --recursive 2>/dev/null || true
} |
    sha |
    awk '{print $1}'
