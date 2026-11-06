#!/bin/sh
# Validate an evidence bundle against the repository in front of you. Exit 0 only when the
# bundle still describes this source; otherwise print one line per problem and exit 1.
#   validate-evidence.sh <plugin-repository> <evidence-directory>
set -eu
exec node "$(dirname "$0")/validate-evidence.mjs" "$@"
