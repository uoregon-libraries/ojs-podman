#!/usr/bin/env bash
#
# Compares OJS's stock config template (config.TEMPLATE.inc.php) between two
# releases, pulled straight from PKP's GitHub tags. With --merge, it applies
# that upstream change to our docker/config/config.base.inc.php in place, so
# the result can be reviewed with "git diff" like any other change.
set -eu

base=./docker/config/config.base.inc.php

usage() {
  echo "Usage: $0 [--merge] <old version> <new version>"
  echo
  echo "Versions are in the Dockerfile's OJS_VERSION form, e.g. 3.5.0-3"
  echo
  echo "Without --merge, prints a diff of the two stock templates."
  echo "With --merge, merges that diff into $base"
  exit 1
}

merge=0
if [[ "${1:-}" == "--merge" ]]; then
  merge=1
  shift
fi

old="${1:-}"
new="${2:-}"
if [[ -z "$old" || -z "$new" || -n "${3:-}" ]]; then
  usage
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# PKP tags releases with underscores in place of dots: 3.5.0-6 is 3_5_0-6
fetch() {
  local tag=${1//./_}
  local url="https://raw.githubusercontent.com/pkp/ojs/$tag/config.TEMPLATE.inc.php"
  if ! curl -fsSL -o "$2" "$url"; then
    echo "Unable to fetch the config template for OJS $1 ($url)" >&2
    exit 1
  fi
}

fetch "$old" "$tmp/old.php"
fetch "$new" "$tmp/new.php"

if [[ $merge == 0 ]]; then
  # diff exits 1 when the files differ, which isn't an error here
  diff -u --label "ojs-$old" --label "ojs-$new" "$tmp/old.php" "$tmp/new.php" || true
  exit 0
fi

# git merge-file returns the number of conflicts, or a negative value on error
# (which the shell sees as a large number)
set +e
git merge-file -L ours -L "ojs-$old" -L "ojs-$new" "$base" "$tmp/old.php" "$tmp/new.php"
conflicts=$?
set -e

if [[ $conflicts == 0 ]]; then
  echo "Merged OJS $old -> $new changes into $base cleanly; review with \"git diff\""
elif [[ $conflicts -lt 128 ]]; then
  echo "Merged OJS $old -> $new changes into $base with $conflicts conflict(s)."
  echo "Resolve the conflict markers, then review with \"git diff\""
  exit 1
else
  echo "git merge-file failed" >&2
  exit 1
fi
