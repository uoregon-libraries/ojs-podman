#!/usr/bin/env bash
#
# Lists plugins (as "category/name") that exist in only one of two plugin
# sources. Each source is either a plugins directory (e.g., a podman volume's
# _data dir) or "image:<ref>" to use the pristine plugins baked into an OJS
# image.
#
# Comparing a volume against the image it runs on shows exactly what came from
# the gallery or a manual upload. Use an image with the *same* OJS version as
# the volume, or core plugins added/dropped between versions show up too.
#
# Rootless podman volumes are owned by subuids, so run this inside `podman
# unshare` when reading them directly.
set -euo pipefail

default_b=image:localhost/journals_web

usage() {
  echo "Usage: $0 <plugins dir | image:ref> [plugins dir | image:ref]"
  echo
  echo "The second source defaults to $default_b"
  echo
  echo "Examples:"
  echo "  $0 vols/plugins"
  echo "  $0 vols/plugins vols/other-plugins"
  exit 1
}

list_plugins() {
  local src=$1
  if [[ $src == image:* ]]; then
    podman run --rm --entrypoint find "${src#image:}" \
      /var/www/html/plugins -mindepth 2 -maxdepth 2 -type d -printf '%P\n'
  elif [[ -d $src ]]; then
    find "$src" -mindepth 2 -maxdepth 2 -type d -printf '%P\n'
  else
    echo "Not a directory or image:ref: $src" >&2
    return 1
  fi
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
fi

src_a=$1
src_b=${2:-$default_b}

# Plain assignments (not process substitution) so set -e catches failures,
# e.g., permission errors from forgetting `podman unshare`
a=$(list_plugins "$src_a" | sort)
b=$(list_plugins "$src_b" | sort)

echo "Only in $src_a:"
comm -23 <(echo "$a") <(echo "$b") | sed 's/^/  /'
echo
echo "Only in $src_b:"
comm -13 <(echo "$a") <(echo "$b") | sed 's/^/  /'
