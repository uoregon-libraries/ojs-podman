#!/usr/bin/env bash
#
# Copies files between podman volumes and directories with rsync, using the
# directory that actually holds a volume's files. That isn't always the
# volume's Mountpoint: a volume with driver_opts (a bind to a "device"
# directory, as in compose.override-example.yml) keeps its files in the device
# directory, and its Mountpoint only shows them inside podman's namespace while
# a container is using the volume. Otherwise the Mountpoint is an empty
# directory, and anything written there never reaches a container.
#
# Each of <src> and <dest> is a directory or "vol:<volume name>". Like rsync
# with trailing slashes on both, this copies what's in <src> into <dest>.
# Options before them go to rsync, which always gets -a, and -r for
# --files-from (which turns off the recursion -a implies).
#
# rsync runs inside `podman unshare`, since files in rootless volumes belong to
# subuids. See "Volume files" in README.md.
set -euo pipefail

usage() {
  echo "Usage: $0 [rsync options] <src> <dest>"
  echo
  echo "Each of <src> and <dest> is a directory or vol:<volume name>"
  echo
  echo "Examples:"
  echo "  $0 vol:ojs-prod_plugins /path/to/backup/plugins"
  echo "  $0 --delete vol:ojs-prod_public-files vol:ojs-dev_public-files"
  exit 1
}

# Prints the directory for a src or dest. Directories pass through as is,
# since rsync creates a missing dest, but a volume's directory has to exist.
resolve() {
  local arg=$1 dir
  if [[ $arg != vol:* ]]; then
    echo "$arg"
    return
  fi

  dir=$(podman volume inspect --format '{{or .Options.device .Mountpoint}}' "${arg#vol:}") || return 1
  if [[ -z $dir || ! -d $dir ]]; then
    echo "Volume ${arg#vol:} has no directory at \"$dir\"" >&2
    return 1
  fi
  echo "$dir"
}

if [[ $# -lt 2 ]]; then
  usage
fi

opts=("${@:1:$#-2}")
src=$(resolve "${*: -2:1}") || exit 1
dest=$(resolve "${*: -1}") || exit 1

if [[ -z $src || -z $dest ]]; then
  usage
fi

echo "Syncing $src/ to $dest/" >&2
podman unshare rsync -ar "${opts[@]}" "$src/" "$dest/"
