#!/bin/sh
# prepare-storage.sh <plugin-repository>
#
# Make <repository>/.code-reviews/ the place evidence and reports are written, and keep it out
# of Git without editing the tracked .gitignore (it is added to the repository's local
# .git/info/exclude instead). Review reports describe weaknesses, so they never belong in a
# public repository.
#
# Set PLUGIN_REVIEW_STORE to keep evidence outside the repository altogether: the folder
# becomes $PLUGIN_REVIEW_STORE/<repository-name>/.code-reviews and .code-reviews is a symlink
# to it. Refuses to replace an existing .code-reviews that is not what it expects.
set -eu

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <plugin-repository>" >&2
    exit 2
fi

repo=$(git -C "$1" rev-parse --show-toplevel)
link="$repo/.code-reviews"

if [ -n "${PLUGIN_REVIEW_STORE:-}" ]; then
    target="$PLUGIN_REVIEW_STORE/$(basename "$repo")/.code-reviews"
    mkdir -p "$target"
    target=$(cd "$target" && pwd)
    if [ -L "$link" ]; then
        current=$(cd "$link" && pwd -P)
        [ "$current" = "$(cd "$target" && pwd -P)" ] || { echo "$link points to $current, expected $target" >&2; exit 1; }
    elif [ -e "$link" ]; then
        echo "$link exists and is not a symlink; refusing to replace it" >&2
        exit 1
    else
        ln -s "$target" "$link"
    fi
else
    if [ -L "$link" ]; then
        echo "$link is a symlink; set PLUGIN_REVIEW_STORE to the store it belongs to" >&2
        exit 1
    fi
    mkdir -p "$link"
fi
mkdir -p "$link/evidence" "$link/reviews"

if ! git -C "$repo" check-ignore -q .code-reviews; then
    # In a linked worktree .git is a file, so ask Git where the exclude file lives.
    exclude=$(git -C "$repo" rev-parse --git-path info/exclude)
    case "$exclude" in /*) ;; *) exclude="$repo/$exclude" ;; esac
    mkdir -p "$(dirname "$exclude")"
    printf '\n/.code-reviews\n' >> "$exclude"
fi

printf '%s\n' "$link"
